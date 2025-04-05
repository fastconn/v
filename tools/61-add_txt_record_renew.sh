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

# 配置文件路径
CONFIG_FILE="$(dirname "$0")/namecheap_api.conf"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    echo "Please create the configuration file with your Namecheap API credentials"
    exit 1
fi

# 从配置文件读取API凭据
source "$CONFIG_FILE"

# 检查Namecheap API配置
if [ -z "$NAMECHEAP_API_USER" ] || [ -z "$NAMECHEAP_API_KEY" ] || [ -z "$NAMECHEAP_CLIENT_IP" ]; then
    echo "Error: Namecheap API configuration is missing or incomplete"
    echo "Please check your configuration file: $CONFIG_FILE"
    exit 1
fi

# 检查TXT记录文件是否存在
if [ ! -f "$TXT_RECORDS_FILE" ]; then
    echo "Error: TXT records file not found: $TXT_RECORDS_FILE"
    echo "Please run generate_cert_txt.sh first"
    exit 1
fi

# 设置Namecheap默认DNS的函数
set_basic_dns() {
    local domain="$1"
    local sld=$(echo "$domain" | cut -d. -f1)
    local tld=$(echo "$domain" | cut -d. -f2)
    
    echo "Setting namespace basicDNS for $domain..."
    
    # 调用Namecheap API设置默认DNS
    response=$(curl -s "https://api.namecheap.com/xml.response" \
        -d "ApiUser=$NAMECHEAP_API_USER" \
        -d "ApiKey=$NAMECHEAP_API_KEY" \
        -d "UserName=$NAMECHEAP_API_USER" \
        -d "ClientIp=$NAMECHEAP_CLIENT_IP" \
        -d "Command=namecheap.domains.dns.setDefault" \
        -d "SLD=$sld" \
        -d "TLD=$tld")
    
    # 检查API响应
    if echo "$response" | grep -q "Status=\"OK\""; then
        echo "Successfully set default DNS for $domain"
        return 0
    else
        echo "Error: Failed to set default DNS for $domain"
        echo "API Response: $response"
        return 1
    fi
}

# 获取现有DNS记录的函数
get_dns_records() {
    local domain="$1"
    local sld=$(echo "$domain" | cut -d. -f1)
    local tld=$(echo "$domain" | cut -d. -f2)
    
    echo "Getting existing DNS records for $domain..."
    
    # 调用Namecheap API获取DNS记录
    response=$(curl -s "https://api.namecheap.com/xml.response" \
        -d "ApiUser=$NAMECHEAP_API_USER" \
        -d "ApiKey=$NAMECHEAP_API_KEY" \
        -d "UserName=$NAMECHEAP_API_USER" \
        -d "ClientIp=$NAMECHEAP_CLIENT_IP" \
        -d "Command=namecheap.domains.dns.getHosts" \
        -d "SLD=$sld" \
        -d "TLD=$tld")
    
    # 检查API响应
    if echo "$response" | grep -q "Status=\"OK\""; then
        echo "$response"
        return 0
    else
        echo "Error: Failed to get DNS records for $domain"
        echo "API Response: $response"
        return 1
    fi
}

# 添加DNS TXT记录的函数
add_dns_txt_records() {
    local domain="$1"
    local sld=$(echo "$domain" | cut -d. -f1)
    local tld=$(echo "$domain" | cut -d. -f2)
    
    echo "Adding TXT records for $domain..."
    
    # 获取现有DNS记录
    if ! existing_records=$(get_dns_records "$domain"); then
        echo "Error: Failed to get existing DNS records"
        return 1
    fi
    
    # 解析现有记录
    echo "Parsing existing DNS records..."
    # 使用成功的方法1解析XML
    records=$(echo "$existing_records" | grep -o '<host[^>]*>')
    
    # 准备API请求参数
    params="ApiUser=$NAMECHEAP_API_USER&ApiKey=$NAMECHEAP_API_KEY&UserName=$NAMECHEAP_API_USER&Command=namecheap.domains.dns.setHosts&ClientIp=$NAMECHEAP_CLIENT_IP&SLD=${DOMAIN%.*}&TLD=${DOMAIN#*.}"
    
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
        
        if [ -n "$name" ] && [ -n "$type" ] && [ -n "$address" ] && [ -n "$ttl" ]; then
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
    
    # 然后添加新的TXT记录
    echo "Adding new TXT records..."
    while IFS=: read -r domain value; do
        host="_acme-challenge"
        record_count=$((record_count + 1))
        params="$params&HostName$record_count=$host&RecordType$record_count=TXT&Address$record_count=$value&TTL$record_count=60"
        echo "Adding new TXT record: $host TXT $value"
        
        # 统计记录类型
        type_counts["TXT"]=$((type_counts["TXT"] + 1))
        
        # 统计子域名
        subdomain_counts[$host]=$((subdomain_counts[$host] + 1))
    done < "$TXT_RECORDS_FILE"
    
    # 调用Namecheap API设置所有DNS记录
    response=$(curl -s "https://api.namecheap.com/xml.response" -d "$params")
    
    # 检查API响应
    if echo "$response" | grep -q "Status=\"OK\""; then
        echo "Successfully added TXT records for $domain"
        echo "Total records preserved and added: $record_count"
        
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
        return 0
    else
        echo "Error: Failed to add TXT records for $domain"
        echo "API Response: $response"
        return 1
    fi
}

# 设置默认DNS
if ! set_basic_dns "$DOMAIN"; then
    echo "Error: Failed to set default DNS"
    exit 1
fi

# 等待DNS设置生效
echo "Waiting for set basicDNS to propagate (10 seconds)..."
sleep 10

# 添加所有TXT记录
if ! add_dns_txt_records "$DOMAIN"; then
    echo "Error: Failed to add DNS TXT records"
    exit 1
fi

# 等待DNS记录传播
echo -e "\nWaiting for DNS records to propagate (10 seconds)..."
sleep 10

# 验证DNS记录是否正确添加并续期证书
echo -e "\nVerifying DNS records and renewing certificate..."
/root/.acme.sh/acme.sh --renew \
    --dns \
    -d "$DOMAIN" \
    -d "$WILDCARD_DOMAIN" \
    --yes-I-know-dns-manual-mode-enough-go-ahead-please

if [ $? -ne 0 ]; then
    echo "Error: DNS verification failed"
    echo "Please check if the DNS records have been properly added"
    exit 1
fi

# 显示证书位置
echo -e "\nCertificates generated successfully:"
echo "Certificate location: /root/.acme.sh/$DOMAIN/"
echo "You can find the following files:"
echo "- fullchain.cer"
echo "- $DOMAIN.cer"
echo "- $DOMAIN.key"
echo "- ca.cer"

echo "Certificate generation and DNS record update completed successfully" 