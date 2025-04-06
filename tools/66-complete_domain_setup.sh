#!/bin/bash

# 检查是否提供了正确的参数
if [ $# -ne 2 ]; then
    echo "Usage: $0 <domain> <ip_list_file>"
    echo "Example: $0 example.com ip_list.txt"
    exit 1
fi

DOMAIN="$1"
IP_LIST_FILE="$2"
SCRIPT_DIR="$(dirname "$0")"

# 检查IP列表文件是否存在
if [ ! -f "$IP_LIST_FILE" ]; then
    echo "Error: IP list file '$IP_LIST_FILE' not found"
    exit 1
fi

# 步骤1: 生成证书TXT记录
echo "Step 1: Generating certificate TXT records..."
if ! "$SCRIPT_DIR/60-generate_cert_txt.sh" "$DOMAIN"; then
    echo "Error: Failed to generate certificate TXT records"
    exit 1
fi

# 步骤2: 添加TXT记录到Namecheap
echo "Step 2: Adding TXT records to Namecheap..."
if ! "$SCRIPT_DIR/61-add_txt_record_renew.sh" "$DOMAIN"; then
    echo "Error: Failed to add TXT records to Namecheap"
    exit 1
fi

# 等待DNS记录生效
echo "Waiting for DNS records to propagate (60 seconds)..."
sleep 60

# 步骤3: 添加A记录到Namecheap
echo "Step 3: Adding A records to Namecheap..."
if ! "$SCRIPT_DIR/62-add_dns_a_records.sh" "$DOMAIN" "$IP_LIST_FILE"; then
    echo "Error: Failed to add A records to Namecheap"
    exit 1
fi

# 等待DNS记录生效
echo "Waiting for DNS records to propagate (60 seconds)..."
sleep 60

# 步骤4: 部署证书到远程服务器
echo "Step 4: Deploying certificates to remote servers..."
if ! "$SCRIPT_DIR/63-deploy_cert_remote.sh" "$DOMAIN" "$IP_LIST_FILE"; then
    echo "Error: Failed to deploy certificates to remote servers"
    exit 1
fi

echo "All steps completed successfully!"
echo "Domain setup process finished for: $DOMAIN" 