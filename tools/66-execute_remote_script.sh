#!/bin/bash

# 检查是否提供了正确的参数
if [ $# -ne 2 ]; then
    echo "Usage: $0 <ip_list_file> <command>"
    echo "Example: $0 ip_list.txt 'systemctl restart v2ray'"
    exit 1
fi

IP_LIST_FILE="$1"
COMMAND="$2"
SSH_USER="root"

# 检查IP列表文件是否存在
if [ ! -f "$IP_LIST_FILE" ]; then
    echo "Error: IP list file '$IP_LIST_FILE' not found"
    exit 1
fi

# 读取IP列表
echo "Reading IP list from $IP_LIST_FILE..."
mapfile -t ips < "$IP_LIST_FILE"

# 统计总IP数
total_ips=${#ips[@]}
echo "Found $total_ips IP addresses to process"

# 处理每个IP
success_count=0
fail_count=0
for ip in "${ips[@]}"; do
    # 验证IP地址格式
    if ! [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Invalid IP address format: $ip"
        fail_count=$((fail_count + 1))
        continue
    fi

    echo -e "\nProcessing $ip..."
    echo "----------------------------------------"

    # 检查SSH连接
    echo "Checking SSH connection..."
    if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$SSH_USER@$ip" "echo 'SSH connection successful'" 2>/dev/null; then
        echo "Error: Failed to connect to $ip via SSH"
        fail_count=$((fail_count + 1))
        continue
    fi

    # 在远程机器上执行命令
    echo "Executing command on remote machine..."
    if ! ssh -o StrictHostKeyChecking=no "$SSH_USER@$ip" "$COMMAND"; then
        echo "Error: Command execution failed on $ip"
        fail_count=$((fail_count + 1))
        continue
    fi

    echo "Successfully executed command on $ip"
    success_count=$((success_count + 1))
done

# 显示执行结果统计
echo -e "\nExecution Summary:"
echo "----------------------------------------"
echo "Total IPs processed: $total_ips"
echo "Successful executions: $success_count"
echo "Failed executions: $fail_count"

# 如果所有执行都失败，返回错误状态
if [ $success_count -eq 0 ]; then
    echo "Error: All executions failed"
    exit 1
fi 