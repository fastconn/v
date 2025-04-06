#!/bin/bash

# 检查acme.sh是否已安装
if [ ! -f "/root/.acme.sh/acme.sh" ]; then
    echo "Error: acme.sh is not installed"
    echo "Please install acme.sh first:"
    echo "curl https://get.acme.sh | sh"
    exit 1
fi

# 设置提醒天数（默认30天）
WARNING_DAYS=${1:-30}

# 获取当前日期
CURRENT_DATE=$(date +%s)

# 检查所有证书
echo "Checking certificates in /root/.acme.sh/..."
for domain_dir in /root/.acme.sh/*/; do
    if [ -d "$domain_dir" ]; then
        domain=$(basename "$domain_dir")
        cert_file="$domain_dir/fullchain.cer"
        
        if [ -f "$cert_file" ]; then
            # 获取证书到期时间
            expiry_date=$(openssl x509 -in "$cert_file" -enddate -noout | cut -d= -f2)
            expiry_timestamp=$(date -d "$expiry_date" +%s)
            
            # 计算剩余天数
            days_remaining=$(( (expiry_timestamp - CURRENT_DATE) / 86400 ))
            
            # 显示证书信息
            echo "Domain: $domain"
            echo "Expiry Date: $expiry_date"
            echo "Days Remaining: $days_remaining"
            
            # 检查是否需要提醒
            if [ "$days_remaining" -le "$WARNING_DAYS" ]; then
                echo "WARNING: Certificate for $domain will expire in $days_remaining days!"
                echo "Please renew the certificate and deploy it to all servers."
                echo "Use the following commands:"
                echo "1. Renew certificate: ./tools/60-generate_cert_txt.sh $domain"
                echo "2. Add TXT records: ./tools/61-add_txt_record_renew.sh $domain"
                echo "3. Deploy to servers: ./tools/62-deploy_cert_remote.sh $domain ip_list.txt"
                echo "----------------------------------------"
            else
                echo "Certificate is valid for $days_remaining more days."
                echo "----------------------------------------"
            fi
        fi
    fi
done

# 创建crontab任务（如果不存在）
if ! crontab -l | grep -q "check_cert_expiry.sh"; then
    echo "Adding daily check to crontab..."
    (crontab -l 2>/dev/null; echo "0 0 * * * $(pwd)/tools/67-check_cert_expiry.sh $WARNING_DAYS") | crontab -
    echo "Daily certificate check has been scheduled."
fi 