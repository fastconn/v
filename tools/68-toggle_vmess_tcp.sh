#!/bin/bash

# 检查是否提供了正确的参数
if [ $# -ne 2 ]; then
    echo "Usage: $0 <ip> <enable/disable>"
    echo "Example: $0 192.168.1.1 enable"
    exit 1
fi

IP="$1"
ACTION="$2"
V2RAY_CONFIG="/etc/v2ray-agent/v2ray/conf/07_VMESS_inbounds.json"
SSH_USER="root"
VMESS_PORT=22324

# 验证IP地址格式
if ! [[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid IP address format: $IP"
    exit 1
fi

# 验证操作参数
if [ "$ACTION" != "enable" ] && [ "$ACTION" != "disable" ]; then
    echo "Error: Action must be either 'enable' or 'disable'"
    exit 1
fi

# 检查SSH连接
echo "Checking SSH connection to $IP..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$IP" "echo 'SSH connection successful'"; then
    echo "Error: Failed to connect to $IP via SSH"
    exit 1
fi

# 检查ufw是否安装
echo "Checking if ufw is installed..."
if ! ssh "$SSH_USER@$IP" "command -v ufw >/dev/null 2>&1"; then
    echo "Error: ufw is not installed on $IP"
    exit 1
fi

# 检查ufw是否启用，如果没有则启用它
echo "Checking ufw status..."
if ! ssh "$SSH_USER@$IP" "ufw status | grep -q 'Status: active'"; then
    echo "ufw is not active, enabling it..."
    ssh "$SSH_USER@$IP" "ufw --force enable"
    
    # 确保SSH端口保持开放
    ssh "$SSH_USER@$IP" "ufw allow 22/tcp"
    
    # 检查是否成功启用
    if ! ssh "$SSH_USER@$IP" "ufw status | grep -q 'Status: active'"; then
        echo "Error: Failed to enable ufw"
        exit 1
    fi
    echo "ufw has been enabled successfully"
fi

# 控制端口
echo "Modifying ufw rules for port $VMESS_PORT..."
if [ "$ACTION" = "enable" ]; then
    # 允许端口
    echo "Allowing port $VMESS_PORT..."
    ssh "$SSH_USER@$IP" "ufw allow $VMESS_PORT/tcp"
else
    # 拒绝端口
    echo "Denying port $VMESS_PORT..."
    ssh "$SSH_USER@$IP" "ufw deny $VMESS_PORT/tcp"
fi

# 检查操作是否成功
if [ $? -ne 0 ]; then
    echo "Error: Failed to modify ufw rules"
    exit 1
fi

# 显示当前端口状态
echo "Current ufw status for port $VMESS_PORT:"
ssh "$SSH_USER@$IP" "ufw status | grep $VMESS_PORT"

echo "Successfully $ACTION VMESS TCP port $VMESS_PORT on $IP" 