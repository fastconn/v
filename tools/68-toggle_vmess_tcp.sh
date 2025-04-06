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

# 检查配置文件是否存在
echo "Checking if v2ray configuration file exists..."
if ! ssh "$SSH_USER@$IP" "[ -f $V2RAY_CONFIG ]"; then
    echo "Error: v2ray configuration file not found at $V2RAY_CONFIG"
    exit 1
fi

# 备份配置文件
echo "Backing up configuration file..."
ssh "$SSH_USER@$IP" "cp $V2RAY_CONFIG ${V2RAY_CONFIG}.bak"

# 获取当前端口
echo "Getting current port..."
CURRENT_PORT=$(ssh "$SSH_USER@$IP" "grep -o '\"port\": [0-9]*,' $V2RAY_CONFIG | grep -o '[0-9]*'")
echo "Current port: $CURRENT_PORT"

# 修改配置文件
echo "Modifying configuration file..."
if [ "$ACTION" = "enable" ]; then
    # 启用VMESS TCP - 恢复原始端口
    NEW_PORT=22324
    echo "Changing port from $CURRENT_PORT to $NEW_PORT (enabling VMESS TCP)"
    ssh "$SSH_USER@$IP" "sed -i 's/\"port\": $CURRENT_PORT,/\"port\": $NEW_PORT,/' $V2RAY_CONFIG"
else
    # 禁用VMESS TCP - 设置端口为1
    NEW_PORT=1
    echo "Changing port from $CURRENT_PORT to $NEW_PORT (disabling VMESS TCP)"
    ssh "$SSH_USER@$IP" "sed -i 's/\"port\": $CURRENT_PORT,/\"port\": $NEW_PORT,/' $V2RAY_CONFIG"
fi

# 检查修改是否成功
if [ $? -ne 0 ]; then
    echo "Error: Failed to modify configuration file"
    echo "Restoring from backup..."
    ssh "$SSH_USER@$IP" "mv ${V2RAY_CONFIG}.bak $V2RAY_CONFIG"
    exit 1
fi

# 重启v2ray服务
echo "Restarting v2ray service..."
ssh "$SSH_USER@$IP" "systemctl restart v2ray"

# 检查服务状态
echo "Checking v2ray service status..."
if ! ssh "$SSH_USER@$IP" "systemctl is-active v2ray"; then
    echo "Error: Failed to restart v2ray service"
    echo "Restoring from backup..."
    ssh "$SSH_USER@$IP" "mv ${V2RAY_CONFIG}.bak $V2RAY_CONFIG"
    ssh "$SSH_USER@$IP" "systemctl restart v2ray"
    exit 1
fi

echo "Successfully $ACTION VMESS TCP connection on $IP (port changed from $CURRENT_PORT to $NEW_PORT)" 