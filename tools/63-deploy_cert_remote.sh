#!/bin/bash

# 检查是否提供了正确的参数
if [ $# -ne 2 ]; then
    echo "Usage: $0 <domain> <ip_list_file>"
    echo "Example: $0 example.com ip_list.txt"
    exit 1
fi

DOMAIN="$1"
IP_LIST_FILE="$2"
SSH_USER="root"

# 提取主域名（如果提供的是子域名）
MAIN_DOMAIN=$(echo "$DOMAIN" | awk -F. '{if (NF>2) print $(NF-1)"."$NF; else print $0}')
SOURCE_DIR="/root/.acme.sh/$MAIN_DOMAIN"
TARGET_DIR="/etc/v2ray-agent/tls"
NGINX_CONF="/etc/nginx/conf.d/alone.conf"

# 检查IP列表文件是否存在
if [ ! -f "$IP_LIST_FILE" ]; then
    echo "Error: IP list file '$IP_LIST_FILE' not found"
    exit 1
fi

# 检查证书文件是否存在
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Certificate directory not found: $SOURCE_DIR"
    echo "Please make sure the certificates were generated first"
    exit 1
fi

if [ ! -f "$SOURCE_DIR/fullchain.cer" ] || [ ! -f "$SOURCE_DIR/$MAIN_DOMAIN.key" ]; then
    echo "Error: Certificate files not found in $SOURCE_DIR"
    echo "Please make sure the certificates were generated first"
    exit 1
fi

# 处理每个IP地址
echo "Starting to process IP list..."
mapfile -t ips < "$IP_LIST_FILE"

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
    
    # 复制证书文件
    echo "Copying certificates to server: $target_ip..."
    scp "$SOURCE_DIR/fullchain.cer" "$SSH_USER@$target_ip:$TARGET_DIR/$MAIN_DOMAIN.crt"
    scp "$SOURCE_DIR/$MAIN_DOMAIN.key" "$SSH_USER@$target_ip:$TARGET_DIR/$MAIN_DOMAIN.key"
    
    # 检查SSH连接是否可用
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$target_ip" "echo 'SSH connection successful'" 2>/dev/null; then
        echo "Error: Cannot establish SSH connection to $target_ip"
        echo "Please check:"
        echo "1. Server is running"
        echo "2. SSH service is active"
        echo "3. Firewall allows SSH connections"
        echo "4. SSH credentials are correct"
        continue
    fi
    
    # 在远程服务器上执行操作
    ssh "$SSH_USER@$target_ip" "bash -s" << EOF
        # 设置错误处理
        set -e
        
        # 创建目标目录（如果不存在）
        mkdir -p $TARGET_DIR
        
        # 设置目录权限
        chmod 755 $TARGET_DIR
        
        # 设置证书文件权限
        chmod 644 $TARGET_DIR/$MAIN_DOMAIN.crt
        chmod 600 $TARGET_DIR/$MAIN_DOMAIN.key
        
        # 如果主域名和当前域名不同，需要复制主域名的证书文件
        if [ "$MAIN_DOMAIN" != "$DOMAIN" ]; then
            echo "Copying main domain certificates for subdomain..."
            cp $TARGET_DIR/$MAIN_DOMAIN.crt $TARGET_DIR/$DOMAIN.crt
            cp $TARGET_DIR/$MAIN_DOMAIN.key $TARGET_DIR/$DOMAIN.key
            chmod 644 $TARGET_DIR/$DOMAIN.crt
            chmod 600 $TARGET_DIR/$DOMAIN.key
        fi
        
        # 检查nginx配置文件是否存在
        if [ ! -f "$NGINX_CONF" ]; then
            echo "Error: Nginx configuration file not found: $NGINX_CONF"
            exit 1
        fi
        
        # 查找server_name后的域名（排除 server_name _;）
        old_domain=\$(grep -oP 'server_name\s+(?!_)\K[^;]+' "$NGINX_CONF" | head -n 1 | tr -d ' ' | tr -d '\n')
        if [ -n "\$old_domain" ]; then
            echo "Found old domain: \$old_domain"
            # 使用 perl 替换配置文件中的所有旧域名
            perl -pi -e "s/\$old_domain/$DOMAIN/g" "$NGINX_CONF"
            echo "Replaced all occurrences of \$old_domain with $DOMAIN in nginx configuration"
        else
            echo "No domain found in $NGINX_CONF"
            exit 1
        fi
        
        # 检查nginx配置是否正确
        if ! nginx -t; then
            echo "Error: Nginx configuration test failed"
            exit 1
        fi
        
        # 重启nginx服务
        systemctl restart nginx
        echo "Nginx service restarted successfully"
        
        # 检查并更新v2ray配置文件
        V2RAY_CONF="/etc/v2ray-agent/v2ray/conf/05_VMess_WS_inbounds.json"
        if [ -f "\$V2RAY_CONF" ]; then
            echo "Checking v2ray configuration..."
            # 查找"add"对应的域名
            v2ray_old_domain=\$(grep -o '"add": *"[^"]*"' "\$V2RAY_CONF" | sed 's/"add": *"//;s/"//')
            if [ -n "\$v2ray_old_domain" ] && [ "\$v2ray_old_domain" != "$DOMAIN" ]; then
                echo "Found domain in v2ray config: \$v2ray_old_domain"
                # 使用 perl 替换v2ray配置文件中的所有旧域名
                perl -pi -e "s/\"add\": \"\$v2ray_old_domain\"/\"add\": \"$DOMAIN\"/g" "\$V2RAY_CONF"
                echo "Replaced all occurrences of \$v2ray_old_domain with $DOMAIN in v2ray config"
            else
                echo "No domain change needed in v2ray config"
            fi
        else
            echo "Warning: V2ray configuration file not found: \$V2RAY_CONF"
        fi

        # 检查并更新VLESS TCP配置文件
        VLESS_CONF="/etc/v2ray-agent/v2ray/conf/02_VLESS_TCP_inbounds.json"
        if [ -f "\$VLESS_CONF" ]; then
            echo "Checking VLESS TCP configuration..."
            # 查找"add"对应的域名
            vless_old_domain=\$(grep -o '"add": *"[^"]*"' "\$VLESS_CONF" | sed 's/"add": *"//;s/"//')
            if [ -n "\$vless_old_domain" ] && [ "\$vless_old_domain" != "$DOMAIN" ]; then
                echo "Found domain in VLESS TCP config: \$vless_old_domain"
                # 替换配置文件中的所有旧域名
                perl -pi -e "s/\$vless_old_domain/$DOMAIN/g" "\$VLESS_CONF"
                echo "Replaced all occurrences of \$vless_old_domain with $DOMAIN in VLESS TCP config"
            else
                echo "No domain change needed in VLESS TCP config"
            fi
        else
            echo "Warning: VLESS TCP configuration file not found: \$VLESS_CONF"
        fi

        # 重启v2ray服务
        systemctl restart v2ray
        echo "V2ray service restarted successfully"
EOF
    
    if [ $? -eq 0 ]; then
        echo "Successfully processed server: $target_ip"
    else
        echo "Error: Failed to process server: $target_ip"
    fi
    
    echo "----------------------------------------"
done

echo "Processing complete!" 