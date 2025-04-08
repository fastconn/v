#!/bin/bash

# 检查是否提供了正确的参数
if [ $# -ne 1 ]; then
    echo "Usage: $0 <domain>"
    echo "Example: $0 example.com"
    exit 1
fi

DOMAIN="$1"
CONFIG_FILE="$(dirname "$0")/namecheap_api.conf"

# 从配置文件读取API凭据
source "$CONFIG_FILE"

# 检查Namecheap API配置
if [ -z "$NAMECHEAP_API_USER" ] || [ -z "$NAMECHEAP_API_KEY" ] || [ -z "$NAMECHEAP_CLIENT_IP" ]; then
    echo "Error: Namecheap API configuration is missing or incomplete"
    echo "Please check your configuration file: $CONFIG_FILE"
    exit 1
fi

# 获取域名的主域名和子域名
MAIN_DOMAIN=$(echo "$DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')
SUBDOMAIN=$(echo "$DOMAIN" | sed "s/\.$MAIN_DOMAIN\$//")

# 准备API请求参数
params="ApiUser=$NAMECHEAP_API_USER&ApiKey=$NAMECHEAP_API_KEY&UserName=$NAMECHEAP_API_USER&Command=namecheap.domains.dns.getHosts&ClientIp=$NAMECHEAP_CLIENT_IP&SLD=${MAIN_DOMAIN%.*}&TLD=${MAIN_DOMAIN#*.}"

# 获取DNS记录
echo "Fetching DNS records for $DOMAIN..."
response=$(curl -s "https://api.namecheap.com/xml.response?$params")

# 检查响应
if ! echo "$response" | grep -q "Status=\"OK\""; then
    echo "Error: Failed to fetch DNS records"
    echo "API Response:"
    echo "$response"
    exit 1
fi

# 解析并显示DNS记录
echo -e "\nDNS Records for $DOMAIN:"
echo "----------------------------------------"

# 使用成功的方法解析XML
records=$(echo "$response" | grep -o '<host[^>]*>')

# 统计记录类型
declare -A type_counts
declare -A subdomain_counts

while IFS= read -r host; do
    # 提取记录信息
    name=$(echo "$host" | grep -o 'Name="[^"]*"' | sed 's/Name="//;s/"//')
    type=$(echo "$host" | grep -o 'Type="[^"]*"' | sed 's/Type="//;s/"//')
    address=$(echo "$host" | grep -o 'Address="[^"]*"' | sed 's/Address="//;s/"//')
    ttl=$(echo "$host" | grep -o 'TTL="[^"]*"' | sed 's/TTL="//;s/"//')
    mxpref=$(echo "$host" | grep -o 'MXPref="[^"]*"' | sed 's/MXPref="//;s/"//')
    
    if [ -n "$name" ] && [ -n "$type" ] && [ -n "$address" ] && [ -n "$ttl" ]; then
        # 显示记录
        if [ "$name" = "@" ]; then
            display_name="$MAIN_DOMAIN"
        else
            display_name="$name.$MAIN_DOMAIN"
        fi
        
        if [ "$type" = "MX" ] && [ -n "$mxpref" ]; then
            echo "$display_name ($type) -> $address (Priority: $mxpref, TTL: $ttl)"
        else
            echo "$display_name ($type) -> $address (TTL: $ttl)"
        fi
        
        # 统计记录类型
        type_counts[$type]=$((type_counts[$type] + 1))
        
        # 统计子域名
        if [ "$name" = "@" ]; then
            subdomain="root"
        else
            subdomain="$name"
        fi
        subdomain_counts[$subdomain]=$((subdomain_counts[$subdomain] + 1))
    fi
done <<< "$records"

# 显示汇总信息
echo -e "\nSummary:"
echo "----------------------------------------"
echo "Total records: ${#records[@]}"
echo -e "\nBy record type:"
for type in "${!type_counts[@]}"; do
    echo "- $type: ${type_counts[$type]}"
done
echo -e "\nBy subdomain:"
for subdomain in "${!subdomain_counts[@]}"; do
    if [ "$subdomain" = "root" ]; then
        echo "- $MAIN_DOMAIN: ${subdomain_counts[$subdomain]}"
    else
        echo "- $subdomain.$MAIN_DOMAIN: ${subdomain_counts[$subdomain]}"
    fi
done 