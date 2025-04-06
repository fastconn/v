#!/bin/bash

# 检查是否提供了域名参数
if [ $# -ne 1 ]; then
    echo "Usage: $0 <domain>"
    echo "Example: $0 example.com"
    exit 1
fi

DOMAIN="$1"
WILDCARD_DOMAIN="*.$DOMAIN"
TXT_RECORDS_FILE="$(dirname "$0")/${DOMAIN}_txt_records.txt"

# 检查acme.sh是否已安装
if [ ! -f "/root/.acme.sh/acme.sh" ]; then
    echo "Error: acme.sh is not installed"
    echo "Please install acme.sh first:"
    echo "curl https://get.acme.sh | sh"
    exit 1
fi

# 创建临时文件用于捕获acme.sh输出
TEMP_OUTPUT=$(mktemp)

# 使用acme.sh生成证书，并将输出重定向到临时文件
echo "Generating certificate for $DOMAIN and $WILDCARD_DOMAIN..."
/root/.acme.sh/acme.sh --issue \
    --force \
    --dns \
    -d "$DOMAIN" \
    -d "$WILDCARD_DOMAIN" \
    --yes-I-know-dns-manual-mode-enough-go-ahead-please  2>&1 | tee "$TEMP_OUTPUT"

# 解析DNS TXT记录并保存到文件
echo -e "\nDNS TXT Records to be added:"
declare -a txt_records
current_domain=""
while IFS= read -r line; do
    if [[ "$line" =~ ^\[.*\]\ Domain:\ \'([^\']+)\' ]]; then
        current_domain="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^\[.*\]\ TXT\ value:\ \'([^\']+)\' ]] && [ -n "$current_domain" ]; then
        txt_value="${BASH_REMATCH[1]}"
        txt_records+=("$current_domain:$txt_value")
        echo "Domain: $current_domain"
        echo "TXT Record: $txt_value"
        echo "----------------------------------------"
        current_domain=""
    fi
done < <(cat "$TEMP_OUTPUT")

# 验证TXT记录数量
if [ ${#txt_records[@]} -ne 2 ]; then
    echo "Error: Expected 2 TXT record, but found ${#txt_records[@]}"
    echo "Please check the acme.sh output for errors"
    echo "Raw output:"
    cat "$TEMP_OUTPUT"
    rm -f "$TEMP_OUTPUT"
    exit 1
fi

# 将TXT记录保存到文件
echo "Saving TXT records to $TXT_RECORDS_FILE..."
for record in "${txt_records[@]}"; do
    echo "$record" >> "$TXT_RECORDS_FILE"
done

# 删除临时文件
rm -f "$TEMP_OUTPUT"

echo "TXT records have been saved to $TXT_RECORDS_FILE"
echo "Please run the following command to add DNS records and renew the certificate:"
