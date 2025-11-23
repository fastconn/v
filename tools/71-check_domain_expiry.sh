#!/bin/bash

# 输入文件
INPUT_FILE="online_domains.txt"
OUTPUT_FILE="domains_expiry.txt"
CONFIG_FILE="$(dirname "$0")/namecheap_api.conf"

# 清空或创建输出文件
> "$OUTPUT_FILE"

# 检查输入文件是否存在
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: $INPUT_FILE not found"
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

# 处理每个域名
while IFS= read -r line; do
    # 跳过注释行和空行
    if [[ $line =~ ^# ]] || [[ -z $line ]]; then
        echo "$line" >> "$OUTPUT_FILE"
        echo "$line"
        continue
    fi

    # 提取域名并清理
    original_domain=$(echo "$line" | tr -d '[:space:]')
    
    # 从域名中提取根域名（TLD和二级域名）
    # 例如 sub.example.com 会变成 example.com
    root_domain=$(echo "$original_domain" | awk -F. '{if (NF>2) {print $(NF-1)"."$NF} else {print $0}}')
    
    # 获取域名信息
    echo "Checking $original_domain ..."
    response=$(curl -s "https://api.namecheap.com/xml.response?ApiUser=$NAMECHEAP_API_USER&ApiKey=$NAMECHEAP_API_KEY&UserName=$NAMECHEAP_API_USER&ClientIp=$NAMECHEAP_CLIENT_IP&Command=namecheap.domains.getInfo&DomainName=$root_domain")

    # 检查API响应
    if [[ $response == *"<Error>"* ]]; then
        error_msg=$(echo "$response" | grep -o '<Error>.*</Error>' | sed 's/<Error>\(.*\)<\/Error>/\1/')
        echo "Error for $original_domain: $error_msg"
        echo "$original_domain: Error - $error_msg" >> "$OUTPUT_FILE"
        continue
    fi

    # 提取到期日期
    expiry_date=$(echo "$response" | grep -o '<ExpiredDate>[^<]*</ExpiredDate>' | head -1 | sed 's/<ExpiredDate>\(.*\)<\/ExpiredDate>/\1/')
    
    if [ -n "$expiry_date" ]; then
        # 清理日期字符串，移除多余的空格和换行符
        expiry_date=$(echo "$expiry_date" | tr -d '[:space:]')
        
        # 拆分日期组件
        month=$(echo "$expiry_date" | cut -d'/' -f1)
        day=$(echo "$expiry_date" | cut -d'/' -f2)
        year=$(echo "$expiry_date" | cut -d'/' -f3)
        
        # 格式化日期为 YYYY-MM-DD
        formatted_date="$year-$month-$day"
        
        # 获取当前日期的秒数
        now=$(date +%s)
        
        # 获取到期日期的秒数
        expiry_seconds=$(date -j -f "%Y-%m-%d" "$formatted_date" +%s 2>/dev/null)
        
        # 如果date -j命令失败，尝试使用其他方法
        if [ -z "$expiry_seconds" ]; then
            expiry_seconds=$(date -d "$formatted_date" +%s 2>/dev/null)
        fi
        
        # 计算剩余天数
        if [ -n "$expiry_seconds" ]; then
            days_left=$(( (expiry_seconds - now) / 86400 ))
            echo "$original_domain: $formatted_date (Left $days_left days)" >> "$OUTPUT_FILE"
            echo "  Expiry date: $formatted_date (Left $days_left days)"
        else
            echo "$original_domain: $formatted_date (Unable to calculate days left)" >> "$OUTPUT_FILE"
            echo "  Expiry date: $formatted_date (Unable to calculate days left)"
        fi
    else
        echo "$original_domain: No expiry date found" >> "$OUTPUT_FILE"
        echo "  No expiry date found"
    fi

    # 添加延迟以避免API限制
    sleep 1
done < "$INPUT_FILE"

echo -e "\nResults have been saved to $OUTPUT_FILE" 