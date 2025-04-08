#!/bin/bash

# 输出文件
OUTPUT_FILE="online_servers.txt"
CONFIG_DIR="/var/www/vserver/configs"

# 检查参数
if [ $# -gt 2 ]; then
    echo "Usage: $0 [m|l|a] [m|l|a]"
    echo "  m: only show servers from servers.json"
    echo "  l: only show servers from lightservers.json"
    echo "  a: only show servers from aosu_servers.json"
    exit 1
fi

# 根据第一个参数决定输出方式
if [ "$1" == "m" ] || [ "$1" == "l" ] || [ "$1" == "a" ]; then
    OUTPUT_CMD=""
    OUTPUT_TO_FILE=false
else
    OUTPUT_CMD=">> \"$OUTPUT_FILE\""
    OUTPUT_TO_FILE=true
    # 清空或创建输出文件
    > "$OUTPUT_FILE"
fi

# 根据第一个参数选择要处理的文件
case "$1" in
    m)
        JSON_FILES=("$CONFIG_DIR/servers.json")
        ;;
    l)
        JSON_FILES=("$CONFIG_DIR/lightservers.json")
        ;;
    a)
        JSON_FILES=("$CONFIG_DIR/aosu_servers.json")
        ;;
    *)
        JSON_FILES=(
            "$CONFIG_DIR/servers.json"
            "$CONFIG_DIR/lightservers.json"
            "$CONFIG_DIR/aosu_servers.json"
        )
        ;;
esac

# 处理每个JSON文件
for json_file in "${JSON_FILES[@]}"; do
    # 检查文件是否存在
    if [ ! -f "$json_file" ]; then
        echo "Warning: $json_file not found, skipping..."
        continue
    fi

    # 获取文件名（不含路径）
    filename=$(basename "$json_file")
    
    if [[ "$filename" == "servers.json" ]]; then
        # 处理servers.json中的free和vip服务器
        free_count=$(jq -r '.l[] | select(.name == "Free") | .servers | length' "$json_file")
        eval "echo -e \"\n# servers.json (Free) - $free_count servers\" $OUTPUT_CMD"
        
        # 存储awk输出到临时变量
        awk_output=$(jq -r '.l[] | select(.name == "Free") | .servers[] | "\(.ip)\t\(.city)\t\(.on)"' "$json_file" | 
            awk -F'\t' '{printf("%-20s %-12s %s\n", $1, $2, $3)}')
        # 根据条件输出
        eval "echo \"$awk_output\" $OUTPUT_CMD"
        
        vip_count=$(jq -r '.l[] | select(.name == "VPN Premium") | .servers | length' "$json_file")
        eval "echo -e \"\n# servers.json (VIP) - $vip_count servers\" $OUTPUT_CMD"
        
        # 存储awk输出到临时变量
        awk_output=$(jq -r '.l[] | select(.name == "VPN Premium") | .servers[] | "\(.ip)\t\(.city)\t\(.on)"' "$json_file" | 
            awk -F'\t' '{printf("%-20s %-12s %s\n", $1, $2, $3)}')
        # 根据条件输出
        eval "echo \"$awk_output\" $OUTPUT_CMD"
    elif [[ "$filename" == "lightservers.json" ]]; then
        # 处理lightservers.json中的服务器
        free_count=$(jq -r '.l[] | select(.name == "Free") | .servers | length' "$json_file")
        eval "echo -e \"\n# lightservers.json (Free) - $free_count servers\" $OUTPUT_CMD"
        
        # 存储awk输出到临时变量
        awk_output=$(jq -r '.l[] | select(.name == "Free") | .servers[] | "\(.ip)\t\(.city)\t\(.on)"' "$json_file" | 
            awk -F'\t' '{printf("%-20s %-12s %s\n", $1, $2, $3)}')
        # 根据条件输出
        eval "echo \"$awk_output\" $OUTPUT_CMD"
        
        add_count=$(jq -r '.l[] | select(.name == "Free") | .servers_0328 | length' "$json_file")
        eval "echo -e \"\n# lightservers.json (Additional) - $add_count servers\" $OUTPUT_CMD"
        
        # 存储awk输出到临时变量
        awk_output=$(jq -r '.l[] | select(.name == "Free") | .servers_0328[] | select(.ip != null) | "\(.ip)\t\(.city)\t\(.on)"' "$json_file" | 
            awk -F'\t' '{printf("%-20s %-12s %s\n", $1, $2, $3)}')
        # 根据条件输出
        eval "echo \"$awk_output\" $OUTPUT_CMD"
    elif [[ "$filename" == "aosu_servers.json" ]]; then
        # 处理aosu_servers.json中的服务器
        free_count=$(jq -r '.l[] | select(.name == "Free") | .ips | length' "$json_file")
        eval "echo -e \"\n# aosu_servers.json (Free) - $free_count servers\" $OUTPUT_CMD"
        
        # 存储awk输出到临时变量
        awk_output=$(jq -r '.l[] | select(.name == "Free") | .ips[] | "\(.ip)\t\(.city)\t\(.on)"' "$json_file" | 
            awk -F'\t' '{printf("%-20s %-12s %s\n", $1, $2, $3)}')
        # 根据条件输出
        eval "echo \"$awk_output\" $OUTPUT_CMD"
    fi
done

# 只在输出到文件时显示总结部分
if $OUTPUT_TO_FILE; then
    eval "echo -e \"\n# Summary by Source File\" $OUTPUT_CMD"
    eval "echo \"----------------------------------------\" $OUTPUT_CMD"

    # 显示结果
    awk_output=$(awk '
        /^#/ { 
            if ($2 != "Summary") {  # 跳过总结部分
                if ($3 == "(Free" || $3 == "(VIP)" || $3 == "(Additional") {
                    current_file = $2 " " $3 " " $4
                } else {
                    current_file = $2
                }
                next
            }
        }
        NF == 3 {  # 只处理包含3个字段的行
            ip = $1
            city = $2
            status = $3
            total[current_file]++
            files[current_file] = 1
        }
        END {
            for (file in files) {
                printf("%s: %d servers\n", 
                    file, total[file])
            }
        }
    ' "$OUTPUT_FILE")

    # 根据条件输出
    eval "echo \"$awk_output\" $OUTPUT_CMD"
    echo -e "\n$awk_output"

    echo -e "\nServer information has been saved to $OUTPUT_FILE"
    # echo -e "\nContents of $OUTPUT_FILE:"
    # cat "$OUTPUT_FILE"

fi 