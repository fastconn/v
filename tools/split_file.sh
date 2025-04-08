#!/bin/bash

# 检查是否提供了正确的参数
if [ $# -ne 1 ]; then
    echo "Usage: $0 <input_file>"
    echo "Example: $0 domains.txt"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE1="${INPUT_FILE}.h1"
OUTPUT_FILE2="${INPUT_FILE}.h2"

# 检查输入文件是否存在
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found"
    exit 1
fi

# 计算总行数
TOTAL_LINES=$(wc -l < "$INPUT_FILE")
HALF_LINES=$(( (TOTAL_LINES + 1) / 2 ))

# 创建输出文件
echo "Splitting $INPUT_FILE into two parts..."
echo "Total lines: $TOTAL_LINES"
echo "First half: $HALF_LINES lines"
echo "Second half: $((TOTAL_LINES - HALF_LINES)) lines"

# 分割文件
head -n "$HALF_LINES" "$INPUT_FILE" > "$OUTPUT_FILE1"
tail -n "+$((HALF_LINES + 1))" "$INPUT_FILE" > "$OUTPUT_FILE2"

# 显示结果
echo -e "\nCreated:"
echo "- $OUTPUT_FILE1 ($(wc -l < "$OUTPUT_FILE1") lines)"
echo "- $OUTPUT_FILE2 ($(wc -l < "$OUTPUT_FILE2") lines)"

# 显示每个文件的前几行
echo -e "\nPreview of $OUTPUT_FILE1:"
head -n 3 "$OUTPUT_FILE1"
echo "..."
echo -e "\nPreview of $OUTPUT_FILE2:"
head -n 3 "$OUTPUT_FILE2"
echo "..." 