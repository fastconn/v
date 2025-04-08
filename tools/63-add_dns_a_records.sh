#!/bin/bash

# 检查是否提供了正确的参数
if [ $# -ne 2 ]; then
    echo "Usage: $0 <domain> <ip_list_file|ip_address>"
    echo "Example: $0 example.com ip_list.txt"
    echo "Example: $0 example.com 192.168.1.1"
    exit 1
fi

DOMAIN="$1"
TARGET="$2"
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

# 准备API请求参数
params="ApiUser=$NAMECHEAP_API_USER&ApiKey=$NAMECHEAP_API_KEY&UserName=$NAMECHEAP_API_USER&Command=namecheap.domains.dns.getHosts&ClientIp=$NAMECHEAP_CLIENT_IP&SLD=${MAIN_DOMAIN%.*}&TLD=${MAIN_DOMAIN#*.}"

# 获取现有DNS记录
echo "Fetching existing DNS records..."
response=$(curl -s "https://api.namecheap.com/xml.response?$params")

# 检查响应
if ! echo "$response" | grep -q "Status=\"OK\""; then
    echo "Error: Failed to fetch existing DNS records"
    echo "API Response:"
    echo "$response"
    exit 1
fi

# 解析现有记录
echo "Parsing existing DNS records..."
# 使用成功的方法1解析XML
records=$(echo "$response" | grep -o '<host[^>]*>')

# 准备API请求参数
params="ApiUser=$NAMECHEAP_API_USER&ApiKey=$NAMECHEAP_API_KEY&UserName=$NAMECHEAP_API_USER&Command=namecheap.domains.dns.setHosts&ClientIp=$NAMECHEAP_CLIENT_IP&SLD=${MAIN_DOMAIN%.*}&TLD=${MAIN_DOMAIN#*.}"

# 添加现有记录
record_count=0
declare -A type_counts
declare -A subdomain_counts

while IFS= read -r host; do
    # 提取记录信息
    name=$(echo "$host" | grep -o 'Name="[^"]*"' | sed 's/Name="//;s/"//')
    type=$(echo "$host" | grep -o 'Type="[^"]*"' | sed 's/Type="//;s/"//')
    address=$(echo "$host" | grep -o 'Address="[^"]*"' | sed 's/Address="//;s/"//')
    ttl=$(echo "$host" | grep -o 'TTL="[^"]*"' | sed 's/TTL="//;s/"//')
    
    # 只保留TXT和A记录
    if [ -n "$name" ] && [ -n "$type" ] && [ -n "$address" ] && [ -n "$ttl" ] && { [ "$type" = "TXT" ] || [ "$type" = "A" ]; }; then
        record_count=$((record_count + 1))
        params="$params&HostName$record_count=$name&RecordType$record_count=$type&Address$record_count=$address&TTL$record_count=$ttl"
        
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
echo -e "\nExisting records summary:"
echo "Total records: $record_count"
echo -e "\nBy record type:"
for type in "${!type_counts[@]}"; do
    echo "- $type: ${type_counts[$type]}"
done
echo -e "\nBy subdomain:"
for subdomain in "${!subdomain_counts[@]}"; do
    echo "- $subdomain: ${subdomain_counts[$subdomain]}"
done

# 添加新的A记录
for ip in "${ips[@]}"; do
    # 增加记录计数
    record_count=$((record_count + 1))
    
    # 添加记录参数
    # 对于根域名的A记录，使用@作为主机名
    if [ "$SUBDOMAIN" = "$DOMAIN" ]; then
        # 如果子域名等于完整域名，说明是根域名
        params="$params&HostName$record_count=@&RecordType$record_count=A&Address$record_count=$ip&TTL$record_count=300"
    else
        # 否则使用子域名作为主机名
        params="$params&HostName$record_count=$SUBDOMAIN&RecordType$record_count=A&Address$record_count=$ip&TTL$record_count=300"
    fi
done

if [ $record_count -eq 0 ]; then
    echo "Error: No valid records found"
    exit 1
fi

echo "Updating DNS records for $DOMAIN..."

# 发送API请求
response=$(curl -s "https://api.namecheap.com/xml.response?$params")

# 检查响应
if echo "$response" | grep -q "Status=\"OK\""; then
    echo "Successfully updated DNS records for $DOMAIN"
    echo "Added IPs:"
    for ip in "${ips[@]}"; do
        echo "- $ip"
    done
else
    echo "Error: Failed to update DNS records"
    echo "API Response:"
    echo "$response"
    exit 1
fi

echo "Processing complete!" 