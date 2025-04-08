#!/bin/bash

# 输出文件
OUTPUT_FILE="online_domains.txt"
CONFIG_DIR="/var/www/vserver/configs"

# 清空或创建输出文件
> "$OUTPUT_FILE"

# 要处理的JSON文件列表
JSON_FILES=(
    "$CONFIG_DIR/servers.json"
    "$CONFIG_DIR/lightservers.json"
    "$CONFIG_DIR/aosu_servers.json"
)

# 处理每个JSON文件
for json_file in "${JSON_FILES[@]}"; do
    
    # 检查文件是否存在
    if [ ! -f "$json_file" ]; then
        echo "Warning: $json_file not found, skipping..."
        continue
    fi

    # 获取文件名（不含路径）
    filename=$(basename "$json_file")
    
    # 添加分隔标记
    echo -e "\n# $filename" >> "$OUTPUT_FILE"

    # 使用grep直接查找domain字段
    domains=$(grep -o '"domain": *"[^"]*"' "$json_file" | cut -d'"' -f4)
    
    if [ -n "$domains" ]; then
        echo "$domains" | while read -r domain; do
            if [ -n "$domain" ]; then
                echo "$domain" >> "$OUTPUT_FILE"
            fi
        done
    else
        echo "No domains found in $json_file"
        echo "# No domains found" >> "$OUTPUT_FILE"
    fi
done

# 显示结果
echo -e "\nExtracted domains have been saved to $OUTPUT_FILE"
echo "Total unique domains: $(grep -v '^#' "$OUTPUT_FILE" | grep -v '^$' | wc -l)"
echo -e "\nDomains by source:"
cat "$OUTPUT_FILE" 