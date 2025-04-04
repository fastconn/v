#!/bin/bash

# 检查是否提供了参数
if [ $# -ne 1 ]; then
    echo "Usage: $0 <ip_list_file_or_single_ip>"
    echo "Example: $0 ip_list.txt"
    echo "Example: $0 192.168.1.100"
    exit 1
fi

INPUT="$1"
declare -a ips

# 检查输入是文件还是IP地址
if [[ "$INPUT" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # 如果是IP地址，直接添加到ips数组
    ips=("$INPUT")
else
    # 如果是文件，检查文件是否存在
    if [ ! -f "$INPUT" ]; then
        echo "Error: IP list file '$INPUT' not found"
        exit 1
    fi
    # 从文件读取IP列表
    mapfile -t ips < "$INPUT"
fi

# SSH用户配置
SSH_USER="root"

# 处理每个IP地址
echo "Starting to process IP list..."
for target_ip in "${ips[@]}"; do
    
    # 跳过空行和注释行
    if [[ -z "$target_ip" || "$target_ip" =~ ^[[:space:]]*# ]]; then
        echo "Debug: Skipping empty or comment line"
        continue
    fi
    
    # 去除行首行尾的空白字符
    target_ip=$(echo "$target_ip" | xargs)
    
    # 验证IP地址格式
    if ! [[ "$target_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Warning: Invalid IP address format: $target_ip, skipping..."
        continue
    fi
    
    echo "Processing server: $target_ip"
    
    # 检查SSH连接是否可用（添加更详细的错误信息）
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$target_ip" "echo 'ssh successful'" 2>/dev/null; then
        echo "Error: Cannot establish SSH connection to $target_ip"
        echo "Please check:"
        echo "1. Server is running"
        echo "2. SSH service is active"
        echo "3. Firewall allows SSH connections"
        echo "4. SSH credentials are correct"
        continue
    fi
    
    # 在远程服务器上执行操作
    ssh "$SSH_USER@$target_ip" "bash -s" << 'EOF'
        # 设置错误处理
        set -e
        
        # 检查netplan配置文件是否存在
        if [ ! -f "/etc/netplan/01-netcfg.yaml" ]; then
            echo "Error: Netplan config file not found"
            exit 1
        fi

        # 检查OpenVPN配置文件是否存在
        if [ ! -f "/etc/openvpn/server/server.conf" ]; then
            echo "Error: OpenVPN config file not found"
            exit 1
        fi

        # 备份OpenVPN配置文件
        cp /etc/openvpn/server/server.conf /etc/openvpn/server/server.conf.bak

        # 从netplan文件中获取addresses到routes之间的所有IPv4地址
        ip_addresses=$(sed -n '/addresses:/,/routes:/p' /etc/netplan/01-netcfg.yaml | grep -E "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+" | tr -d " -")
        
        if [ -z "$ip_addresses" ]; then
            echo "Error: Could not find IPv4 addresses in netplan config"
            exit 1
        fi

        # 计算IP地址数量
        ip_count=$(echo "$ip_addresses" | wc -l)
        
        if [ "$ip_count" -eq 1 ]; then
            echo "Only one IP address found, no need to update OpenVPN config"
            exit 0
        fi
        
        # 获取最后一个IP地址
        last_ip=$(echo "$ip_addresses" | tail -n 1)
        
        # 提取IP地址（去掉CIDR掩码）
        ip_address=$(echo "$last_ip" | cut -d'/' -f1)
        echo "Found multiple IP addresses, updating to use: $ip_address"
        
        # 检查是否已经存在local配置
        if grep -q "^local " /etc/openvpn/server/server.conf; then
            # 如果存在，则替换现有的local行
            sed -i "s/^local .*$/local $ip_address/" /etc/openvpn/server/server.conf
        else
            # 如果不存在，则添加新的local行
            # 首先检查是否有注释掉的local行
            if grep -q "^;local " /etc/openvpn/server/server.conf; then
                # 替换注释掉的local行
                sed -i "s/^;local .*$/local $ip_address/" /etc/openvpn/server/server.conf
            else
                # 在配置文件中添加新的local行
                # 在port行之后添加local行
                sed -i "/^port /a\local $ip_address" /etc/openvpn/server/server.conf
            fi
        fi
        
        # 重启OpenVPN服务
        systemctl restart openvpn-server@server
        
        # 等待服务启动
        sleep 2
        
        # 检查服务状态
        if systemctl is-active --quiet openvpn-server@server; then
            echo "Successfully updated OpenVPN to use IP: $ip_address"
            
            # 验证OpenVPN是否正在监听正确的IP
            if netstat -tulpn | grep -q "openvpn.*$ip_address:2328"; then
                echo "Verified: OpenVPN is listening on $ip_address:2328"
            else
                echo "Warning: OpenVPN might not be listening on the correct IP"
            fi
        else
            echo "Error: Failed to restart OpenVPN service"
            # 恢复备份
            cp /etc/openvpn/server/server.conf.bak /etc/openvpn/server/server.conf
            systemctl restart openvpn-server@server
            exit 1
        fi
EOF
    
    if [ $? -eq 0 ]; then
        echo "Successfully processed server: $target_ip"
    else
        echo "Error: Failed to process server: $target_ip"
    fi
    
    echo "----------------------------------------"
done

echo "Processing complete!" 
