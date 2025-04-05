#!/bin/bash

# 检查是否提供了正确的参数
if [ $# -ne 2 ]; then
    echo "Usage: $0 <target_ip> <new_ip>"
    echo "Example: $0 192.168.1.100 192.168.1.200"
    exit 1
fi

TARGET_IP="$1"
NEW_IP="$2"
SSH_USER="root"

# 验证IP地址格式
if ! [[ "$TARGET_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid target IP address format: $TARGET_IP"
    exit 1
fi

# 如果新IP没有包含掩码，自动添加/32
if ! [[ "$NEW_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
    if [[ "$NEW_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        NEW_IP="$NEW_IP/32"
        echo "Automatically added /32 mask to new IP: $NEW_IP"
    else
        echo "Error: Invalid new IP address format: $NEW_IP"
        exit 1
    fi
fi

echo "Processing server: $TARGET_IP add: $NEW_IP"

# 检查SSH连接是否可用
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$TARGET_IP" "echo 'ssh successful'" 2>/dev/null; then
    echo "Error: Cannot establish SSH connection to $TARGET_IP"
    echo "Please check:"
    echo "1. Server is running"
    echo "2. SSH service is active"
    echo "3. Firewall allows SSH connections"
    echo "4. SSH credentials are correct"
    exit 1
fi

# 在远程服务器上执行操作
ssh "$SSH_USER@$TARGET_IP" "bash -s" << EOF
    # 设置错误处理
    set -e
    
    # 检查netplan配置文件是否存在
    if [ ! -f "/etc/netplan/01-netcfg.yaml" ]; then
        echo "Error: Netplan config file not found"
        exit 1
    fi

    # 备份配置文件
    cp /etc/netplan/01-netcfg.yaml /etc/netplan/01-netcfg.yaml.bak

    # 从netplan文件中获取addresses到routes之间的所有IPv4地址
    ip_addresses=\$(sed -n '/addresses:/,/routes:/p' /etc/netplan/01-netcfg.yaml | grep -E "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+" | tr -d " -")
    
    if [ -z "\$ip_addresses" ]; then
        echo "Error: Could not find IPv4 addresses in netplan config"
        exit 1
    fi

    # 获取第一个IP的掩码（直接从文件中获取，确保格式正确）
    first_ip_line=\$(sed -n '/addresses:/,/routes:/p' /etc/netplan/01-netcfg.yaml | grep -E "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+" | head -n 1)
    mask=\$(echo "\$first_ip_line" | grep -o '/[0-9]\+' | tr -d '/')
    
    if [ -z "\$mask" ]; then
        echo "Error: Could not extract mask from first IP"
        exit 1
    fi
    
    # 如果新IP没有掩码或掩码不同，使用第一个IP的掩码
    if [[ "$NEW_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        NEW_IP="$NEW_IP/\$mask"
    elif [[ "$NEW_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        current_mask=\$(echo "$NEW_IP" | cut -d'/' -f2)
        if [ "\$current_mask" != "\$mask" ]; then
            NEW_IP=\$(echo "$NEW_IP" | cut -d'/' -f1)/\$mask
        fi
    fi

    # 检查新IP是否已经存在（只在addresses和routes之间检查）
    if echo "\$ip_addresses" | grep -q "$NEW_IP"; then
        echo "Warning: IP $NEW_IP already exists in the configuration"
        exit 0
    fi

    # 计算IP地址数量
    ip_count=\$(echo "\$ip_addresses" | wc -l)
    
    # 如果IP数量超过3个，删除第二个IP
    if [ "\$ip_count" -ge 3 ]; then
        echo "More than 3 IPs detected, removing the second IP"
        # 获取第二个IP地址
        second_ip=\$(echo "\$ip_addresses" | sed -n '2p')
        # 删除第二个IP地址（使用@作为分隔符，只在addresses和routes之间操作）
        sed -i "/addresses:/,/routes:/ s@$second_ip@@g" /etc/netplan/01-netcfg.yaml
        echo "Removed IP: \$second_ip"
    fi

    # 获取最后一行IP的格式
    last_ip_line=\$(sed -n '/addresses:/,/routes:/p' /etc/netplan/01-netcfg.yaml | grep -E "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+" | tail -n 1)
    
    # 在routes之前添加新IP（使用@作为分隔符，只在addresses和routes之间操作）
    sed -i "/addresses:/,/routes:/ s@routes:@  - $NEW_IP\\n      routes:@g" /etc/netplan/01-netcfg.yaml

    # 应用新的网络配置
    netplan apply

    # 验证新IP是否已添加（只在addresses和routes之间检查）
    if sed -n '/addresses:/,/routes:/p' /etc/netplan/01-netcfg.yaml | grep -q "$NEW_IP"; then
        echo "Successfully added IP $NEW_IP to the configuration"
    else
        echo "Error: Failed to add IP $NEW_IP"
        # 恢复备份
        cp /etc/netplan/01-netcfg.yaml.bak /etc/netplan/01-netcfg.yaml
        netplan apply
        exit 1
    fi
EOF

if [ $? -eq 0 ]; then
    echo "Successfully processed server: $TARGET_IP"
else
    echo "Error: Failed to process server: $TARGET_IP"
fi 