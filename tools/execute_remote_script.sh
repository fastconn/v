#!/bin/bash

# 检查是否提供了正确的参数
if [ $# -ne 2 ]; then
    echo "Usage: $0 <command> <ip_list_file|ip_address>"
    echo "Example: $0 'systemctl restart v2ray' ip_list.txt"
    echo "Example: $0 'systemctl restart v2ray' 192.168.1.1"
    exit 1
fi

COMMAND="$1"
TARGET="$2"
SSH_USER="root"

# 检查第二个参数是文件还是IP地址
if [ -f "$TARGET" ]; then
    # 如果是文件，读取IP列表
    echo "Reading IP list from $TARGET..."
    ips=()
    while IFS= read -r line; do
        # 从行中提取第一个IP地址
        ip=$(echo "$line" | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+' | head -n 1)
        if [ -n "$ip" ]; then
            ips+=("$ip")
        fi
    done < "$TARGET"
else
    # 如果是IP地址，直接使用
    if echo "$TARGET" | grep -q '^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$'; then
        ips=("$TARGET")
    else
        echo "Error: Second parameter must be either a valid IP address or an existing file"
    exit 1
    fi
fi

# 统计总IP数
total_ips=${#ips[@]}
if [ $total_ips -eq 0 ]; then
    echo "Error: No valid IP addresses found"
    exit 1
fi
echo "Found $total_ips IP addresses to process"

# 处理每个IP
success_count=0
fail_count=0
for ip in "${ips[@]}"; do
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