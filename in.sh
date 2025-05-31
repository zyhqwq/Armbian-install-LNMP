#!/bin/bash

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root用户运行此脚本！"
    exit 1
fi

trap "stty sane" EXIT
stty sane
set +e

INSTALL_DIR="/var/www/typecho"

# 禁用 Nginx 默认站点，确保IP访问落到Typecho
if [ -f /etc/nginx/conf.d/default.conf ]; then
    mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
fi
if [ -f /etc/nginx/sites-enabled/default ]; then
    mv /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.bak
fi

# 卸载环境函数
uninstall_env() {
    echo "正在卸载环境（MySQL/MariaDB、Nginx、PHP等）..."
    systemctl stop mariadb mysql nginx php8.3-fpm 2>/dev/null
    apt purge -y mariadb-* mysql-* nginx php8.3* php-common
    rm -rf /etc/mysql /var/lib/mysql /etc/nginx /etc/php /var/www/* /etc/nginx/conf.d/*.conf /etc/nginx/ssl
    rm -rf /var/log/mysql /var/log/nginx /var/log/php* /var/log/mariadb
    rm -rf ~/.acme.sh
    crontab -l | grep -v acme.sh | crontab -
    rm -f /etc/apt/sources.list.d/nginx.list /etc/apt/sources.list.d/php.list
    rm -f /usr/share/keyrings/nginx-archive-keyring.gpg /usr/share/keyrings/deb.sury.org-php.gpg
    apt autoremove -y
    echo "环境已卸载完成。"
    echo ""
    return 0
    return 0
}

# 检查密码复杂度
check_password_complexity() {
    local password=$1
    if [ ${#password} -lt 8 ]; then
        echo "密码必须至少8个字符"
        return 1
    fi
    if ! [[ "$password" =~ [A-Z] ]] || ! [[ "$password" =~ [a-z] ]] || ! [[ "$password" =~ [0-9] ]]; then
        echo "密码必须包含大小写字母和数字"
        return 1
    fi
    return 0
}

# 安装Typecho函数
install_typecho() {
    # 再次禁用默认站点，防止被恢复
    if [ -f /etc/nginx/conf.d/default.conf ]; then
        mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
    fi
    if [ -f /etc/nginx/sites-enabled/default ]; then
        mv /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.bak
    fi

    echo "设置Typecho数据库..."
    while true; do
        stty sane
        read -e -p "请输入Typecho数据库密码: " db_password
        if check_password_complexity "$db_password"; then
            break
        else
            echo "密码不符合复杂度要求，请重新输入"
        fi
    done
    
    stty sane
    read -e -p "请输入MySQL root密码: " DB_ROOT_PASS
    
    mysql -uroot -p"$DB_ROOT_PASS" -e "CREATE DATABASE IF NOT EXISTS typecho;"
    mysql -uroot -p"$DB_ROOT_PASS" -e "CREATE USER IF NOT EXISTS 'typecho'@'localhost' IDENTIFIED BY '$db_password';"
    mysql -uroot -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON typecho.* TO 'typecho'@'localhost';"
    mysql -uroot -p"$DB_ROOT_PASS" -e "FLUSH PRIVILEGES;"

    echo "正在安装Typecho..."
    # 检测网络连接
    if ! curl -s --connect-timeout 5 https://github.com >/dev/null; then
        echo "检测到无法直接访问GitHub，将优先使用国内镜像"
        declare -a download_urls=(
            "https://ghproxy.com/https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
            "https://mirror.ghproxy.com/https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
            "https://gh.api.99988866.xyz/https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
            "https://gh.zyhmifan.top/https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
            "https://github.zyhmifan.top/https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
        )
    else
        declare -a download_urls=(
            "https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
            "https://ghproxy.com/https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
            "https://mirror.ghproxy.com/https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
        )
    fi
    
    echo "正在尝试从以下镜像源下载Typecho..."
    printf '%s\n' "${download_urls[@]}"
    
    download_success=0
    for url in "${download_urls[@]}"; do
        for try in {1..3}; do
            echo "尝试从 $url 下载...（第$try次）"
            if wget --no-check-certificate -T 45 -O typecho.zip "$url"; then
                download_success=1
                echo "下载成功！"
                break 2  # 成功则跳出两层循环
            fi
            echo "下载失败，等待5秒后重试..."
            sleep 5
        done
        echo "该源连续3次下载失败，尝试下一个源..."
    done
    
    if [ "$download_success" -eq 0 ]; then
        echo -e "\n所有自动下载源均失败，请按以下步骤手动操作："
        echo "1. 使用能访问GitHub的设备下载："
        echo "   https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
        echo "2. 将文件上传到服务器的当前目录 ($PWD)"
        echo "3. 确认文件名为typecho.zip"
        echo "4. 重新运行此脚本"
        echo -e "\n如需帮助上传文件，可使用以下命令："
        echo "scp typecho.zip root@your-server-ip:$PWD"
        return 1
    fi
    
    if [ "$download_success" -eq 0 ]; then
        echo "所有下载源均失败，请检查网络或手动下载！"
        return 1
    fi

    mkdir -p "$INSTALL_DIR"
    unzip -o typecho.zip -d "$INSTALL_DIR" || {
        echo "解压Typecho失败，请检查zip文件是否完整"
        return 1
    }
    rm -f typecho.zip   # 立即删除
    chown -R www-data:www-data "$INSTALL_DIR"
    find "$INSTALL_DIR" -type d -exec chmod 755 {} \;
    find "$INSTALL_DIR" -type f -exec chmod 644 {} \;

    # 获取所有本机IP
    ALL_IPS=$(hostname -I | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tr '\n' ' ')

    # SSL证书配置选择
    stty sane
    read -e -p "是否要配置SSL证书？(y/n): " ssl_choice
    if [[ "$ssl_choice" =~ ^[Yy]$ ]]; then
        echo "准备申请SSL证书..."
        while true; do
            stty sane
            read -e -p "请输入您的域名(如example.com，只允许域名): " domain_name
            if [[ "$domain_name" =~ ^[a-zA-Z0-9.-]+$ && ! "$domain_name" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                break
            else
                echo "错误：域名格式无效，请输入有效域名(不要包含http/https)"
                continue
            fi
        done
        stty sane
        read -e -p "请输入您的邮箱: " email_address

        mkdir -p /etc/nginx/ssl/
        apt install -y socat cron

        # 判断 github 是否可访问，否则用国内镜像
        ACME_SH=~/.acme.sh/acme.sh
        if [ ! -f "$ACME_SH" ]; then
            if curl -s --connect-timeout 5 https://github.com/ | grep -q "github"; then
                echo "使用官方 acme.sh 安装脚本"
                curl https://get.acme.sh | sh -s email="$email_address"
            else
                echo "检测到无法访问 github，使用国内镜像安装 acme.sh"
                curl https://gitee.com/neilpang/acme.sh/raw/master/acme.sh | sh -s email="$email_address"
            fi
        fi
        export PATH=~/.acme.sh:$PATH
        $ACME_SH --set-default-ca --server letsencrypt

        echo "检测到你没有公网IP或80端口未开放，推荐使用 DNS API 方式申请证书。"
        stty sane
        read -e -p "请输入DNS服务商标识（如 dnspod、ali、cf 等，留空则跳过，详见 https://github.com/acmesh-official/acme.sh/wiki/dnsapi）: " dns_provider

        if [[ -n "$dns_provider" ]]; then
            case "$dns_provider" in
                dnspod)
                    stty sane
                    read -e -p "请输入DNSPod ID: " DP_Id
                    stty sane
                    read -e -p "请输入DNSPod API Key: " DP_Key
                    export DP_Id
                    export DP_Key
                    dns_flag="--dns dns_dp"
                    ;;
                ali)
                    stty sane
                    read -e -p "请输入Aliyun Access Key ID: " Ali_Key
                    stty sane
                    read -e -p "请输入Aliyun Access Key Secret: " Ali_Secret
                    export Ali_Key
                    export Ali_Secret
                    dns_flag="--dns dns_ali"
                    ;;
                cf)
                    stty sane
                    read -e -p "请输入Cloudflare API Token: " CF_Token
                    export CF_Token
                    dns_flag="--dns dns_cf"
                    ;;
                *)
                    echo "暂不支持该DNS服务商，请参考acme.sh文档手动申请。"
                    return 1
                    ;;
            esac
            ~/.acme.sh/acme.sh --issue $dns_flag -d "$domain_name" -d "www.$domain_name" -k ec-256 || {
                echo "SSL证书申请失败，请检查API信息和域名解析。"
                return 1
            }
        else
            # 仍尝试80端口方式
            ~/.acme.sh/acme.sh --issue --standalone -d "$domain_name" -d "www.$domain_name" -k ec-256 || {
                echo "SSL证书申请失败，请检查域名解析和80端口是否开放"
                return 1
            }
        fi

        ~/.acme.sh/acme.sh --installcert -d "$domain_name" --ecc \
            --fullchain-file "/etc/nginx/ssl/$domain_name.crt" \
            --key-file "/etc/nginx/ssl/$domain_name.key"

        # 生成带SSL的Nginx配置，server_name包含所有本机IP和localhost
        cat > /etc/nginx/conf.d/typecho.conf <<EOF
server {
    listen 80;
    server_name $domain_name www.$domain_name localhost $ALL_IPS;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name $domain_name www.$domain_name localhost $ALL_IPS;
    
    ssl_certificate /etc/nginx/ssl/$domain_name.crt;
    ssl_certificate_key /etc/nginx/ssl/$domain_name.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    root $INSTALL_DIR;
    index index.php index.html;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOF
    else
        while true; do
            stty sane
            echo "你选择不使用SSL证书，继续配置HTTP服务器..."
            read -e -p "请输入您的域名或IP地址: " domain_name
            if [[ "$domain_name" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                IFS='.' read -ra ip_parts <<< "$domain_name"
                valid_ip=1
                for part in "${ip_parts[@]}"; do
                    if ((part < 0 || part > 255)); then
                        valid_ip=0
                        break
                    fi
                done
                if ((valid_ip)); then
                    break
                else
                    echo "错误：IP地址无效，各段应在0-255之间"
                fi
            elif [[ "$domain_name" =~ ^[a-zA-Z0-9.-]+$ ]]; then
                break
            else
                echo "错误：输入格式无效，请输入有效IP或域名"
            fi
        done
        # 生成HTTP Nginx配置，server_name包含所有本机IP和localhost
        cat > /etc/nginx/conf.d/typecho.conf <<EOF
server {
    listen 80;
    server_name $domain_name localhost $ALL_IPS;
    root $INSTALL_DIR;
    index index.php index.html;
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
    location ~ /\.ht {
        deny all;
    }
}
EOF
    fi  # 结束SSL选择判断

    sync
    sleep 2

    echo "正在重启Nginx..."
    nginx -t || { echo "Nginx 配置有误，请检查 /etc/nginx/conf.d/typecho.conf"; return 1; }
    if [ ! -f /etc/nginx/conf.d/typecho.conf ]; then
        echo "Nginx 配置文件写入失败！"
        return 1
    fi
    systemctl restart nginx
    systemctl restart php8.3-fpm

    # 检查端口监听
    if ! ss -tln | grep -q ':80 '; then
        echo "❌ 警告：Nginx 未监听80端口，请检查配置！"
    fi
    if ! ss -tln | grep -q ':443 '; then
        echo "⚠️  警告：Nginx 未监听443端口（如未启用SSL可忽略）"
    fi

    # 安装验证
    TEST_FILE="$INSTALL_DIR/php_test_$(date +%s).php"
    echo "<?php echo 'VALIDATION_SUCCESS'; ?>" > "$TEST_FILE"
    chown www-data:www-data "$TEST_FILE"
    echo -e "\n正在进行安装验证..."
    VALID_URL="http://$domain_name/$(basename "$TEST_FILE")"
    if curl -s --connect-timeout 10 "$VALID_URL" | grep -q "VALIDATION_SUCCESS"; then
        echo "✅ PHP解析验证成功"
    else
        echo "❌ PHP解析验证失败，请检查："
        echo "1. 确保已通过 http://$domain_name 访问"
        echo "2. 检查防火墙设置"
        echo "3. 查看错误日志：tail -n 50 /var/log/nginx/error.log"
    fi
    rm -f "$TEST_FILE"

    echo "=============================================="
    echo "✅ Typecho 安装完成！"
    if [[ "$ssl_choice" =~ ^[Yy]$ ]]; then
        echo "访问地址: https://$domain_name/install.php"
    else
        echo "访问地址: http://$domain_name/install.php"
    fi
    echo "Typecho数据库信息:"
    echo "  数据库名: typecho"
    echo "  用户名: typecho"
    echo "  密码: $db_password"
    echo ""
    echo "请立即记录以上密码信息！"
    echo "=============================================="
    return 0
}

apply_ssl_cert() {
    echo "准备申请SSL证书..."
    stty sane
    read -e -p "请输入您的邮箱: " email_address

    mkdir -p /etc/nginx/ssl/
    apt install -y socat cron

    # 判断 acme.sh 是否已安装
    if [ ! -f ~/.acme.sh/acme.sh ]; then
        if curl -s --connect-timeout 5 https://github.com/ | grep -q "github"; then
            echo "使用官方 acme.sh 安装脚本"
            curl https://get.acme.sh | sh -s email="$email_address"
        else
            echo "检测到无法访问 github，使用国内镜像安装 acme.sh"
            curl https://gitee.com/neilpang/acme.sh/raw/master/acme.sh | sh -s email="$email_address"
        fi
    fi

    export PATH=~/.acme.sh:$PATH
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

    echo "你没有公网IP，推荐使用 DNS API 方式申请证书。请根据你的域名DNS服务商，准备好API密钥。常见支持：阿里云、DNSPod、Cloudflare等，详见 https://github.com/acmesh-official/acme.sh/wiki/dnsapi"
    stty sane
    read -e -p "请输入DNS服务商标识（如 dnspod、ali、cf 等，留空则退出）: " dns_provider

    if [[ -z "$dns_provider" ]]; then
        echo "未输入DNS服务商，无法申请证书。"
        return 1
    fi

    case "$dns_provider" in
        dnspod)
            stty sane
            read -e -p "请输入DNSPod ID: " DP_Id
            stty sane
            read -e -p "请输入DNSPod API Key: " DP_Key
            export DP_Id
            export DP_Key
            dns_flag="--dns dns_dp"
            ;;
        ali)
            stty sane
            read -e -p "请输入Aliyun Access Key ID: " Ali_Key
            stty sane
            read -e -p "请输入Aliyun Access Key Secret: " Ali_Secret
            export Ali_Key
            export Ali_Secret
            dns_flag="--dns dns_ali"
            ;;
        cf)
            stty sane
            read -e -p "请输入Cloudflare API Token: " CF_Token
            export CF_Token
            dns_flag="--dns dns_cf"
            ;;
        *)
            echo "暂不支持该DNS服务商，请参考acme.sh文档手动申请。"
            return 1
            ;;
    esac

    stty sane
    read -e -p "请输入您的域名(如example.com): " domain_name

    ~/.acme.sh/acme.sh --issue $dns_flag -d "$domain_name" -d "www.$domain_name" -k ec-256 || {
        echo "SSL证书申请失败，请检查API信息和域名解析。"
        return 1
    }

    ~/.acme.sh/acme.sh --installcert -d "$domain_name" --ecc \
        --fullchain-file "/etc/nginx/ssl/$domain_name.crt" \
        --key-file "/etc/nginx/ssl/$domain_name.key"

    echo "SSL证书申请并安装完成，证书路径："
    echo "/etc/nginx/ssl/$domain_name.crt"
    echo "/etc/nginx/ssl/$domain_name.key"
    return 0
}

setup_custom_site() {
    # 获取网站目录
    while true; do
        stty sane
        read -e -p "请输入网站文件存放路径 (如 /var/www/my_site): " site_dir
        if [[ -z "$site_dir" ]]; then
            echo "路径不能为空，请重新输入"
            continue
        fi
        if [[ ! -d "$site_dir" ]]; then
            read -e -p "目录不存在，是否创建? (y/n): " create_dir
            if [[ "$create_dir" =~ ^[Yy]$ ]]; then
                mkdir -p "$site_dir" || {
                    echo "创建目录失败，请检查权限"
                    continue
                }
                chown -R www-data:www-data "$site_dir"
                break
            else
                continue
            fi
        else
            break
        fi
    done

    # 获取域名/IP
    while true; do
        stty sane
        read -e -p "请输入您的域名或IP地址(输入_跳过SSL配置): " domain_name
        if [[ "$domain_name" == "_" ]]; then
            ssl_flag=0
            break
        elif [[ "$domain_name" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            IFS='.' read -ra ip_parts <<< "$domain_name"
            valid_ip=1
            for part in "${ip_parts[@]}"; do
                if ((part < 0 || part > 255)); then
                    valid_ip=0
                    break
                fi
            done
            if ((valid_ip)); then
                # 只有输入有效域名/IP时才询问SSL配置
                stty sane
                read -e -p "是否要配置SSL证书？(y/n): " ssl_choice
                if [[ "$ssl_choice" =~ ^[Yy]$ ]]; then
                    apply_ssl_cert || return 1
                    ssl_flag=1
                else
                    ssl_flag=0
                fi
                break
            else
                echo "错误：IP地址无效，各段应在0-255之间"
            fi
        elif [[ "$domain_name" =~ ^[a-zA-Z0-9.-]+$ ]]; then
            # 只有输入有效域名/IP时才询问SSL配置
            stty sane
            read -e -p "是否要配置SSL证书？(y/n): " ssl_choice
            if [[ "$ssl_choice" =~ ^[Yy]$ ]]; then
                apply_ssl_cert || return 1
                ssl_flag=1
            else
                ssl_flag=0
            fi
            break
        else
            echo "错误：输入格式无效，请输入有效IP、域名或_跳过SSL配置"
        fi
    done

    # 获取监听端口
    while true; do
        stty sane
        read -e -p "请输入HTTP监听端口(默认80): " http_port
        http_port=${http_port:-80}
        if [[ "$http_port" =~ ^[0-9]+$ ]] && [ "$http_port" -ge 1 ] && [ "$http_port" -le 65535 ]; then
            break
        else
            echo "错误：端口必须是1-65535之间的数字"
        fi
    done

    # 生成Nginx配置
    if [[ "$domain_name" == "_" ]]; then
        while true; do
            stty sane
            read -e -p "请输入自定义配置文件名(不含.conf后缀): " config_name
            if [[ "$config_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                CONFIG_FILE="/etc/nginx/conf.d/${config_name}.conf"
                break
            else
                echo "错误：文件名只能包含字母、数字、下划线和连字符"
            fi
        done
    else
        CONFIG_FILE="/etc/nginx/conf.d/${domain_name}.conf"
    fi
    if [ $ssl_flag -eq 1 ]; then
        while true; do
            stty sane
            read -e -p "请输入HTTPS监听端口(默认443): " https_port
            https_port=${https_port:-443}
            if [[ "$https_port" =~ ^[0-9]+$ ]] && [ "$https_port" -ge 1 ] && [ "$https_port" -le 65535 ]; then
                break
            else
                echo "错误：端口必须是1-65535之间的数字"
            fi
        done

        cat > "$CONFIG_FILE" <<EOF
server {
    listen $http_port;
    server_name $domain_name;
    return 301 https://\$host\$request_uri;
}

server {
    listen $https_port ssl;
    server_name $domain_name;
    
    ssl_certificate /etc/nginx/ssl/$domain_name.crt;
    ssl_certificate_key /etc/nginx/ssl/$domain_name.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    root $site_dir;
    index index.php index.html;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF
    else
        cat > "$CONFIG_FILE" <<EOF
server {
    listen $http_port;
    server_name localhost;
    root $site_dir;
    index index.php index.html;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    location ~ \.php\$ {
        include fastcgi_params;
        fastcgi_pass 127.0.0.1:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF
    fi

    # 测试并重启服务
    nginx -t || {
        echo "Nginx配置测试失败"
        return 1
    }
    systemctl restart nginx
    systemctl restart php8.3-fpm

    echo "=============================================="
    echo "✅ 自定义网站配置完成！"
    if [[ "$domain_name" == "_" ]]; then
        echo "访问地址: http://localhost 或服务器IP"
    elif [ $ssl_flag -eq 1 ]; then
        echo "访问地址: https://$domain_name"
    else
        echo "访问地址: http://$domain_name"
    fi
    echo "网站目录: $site_dir"
    echo "=============================================="
    return 0
}

while true; do
    echo "1) 安装网站环境（MySQL、Nginx、PHP等）"
    echo "2) 仅安装Typecho（需已安装好环境）"
    echo "3) 完整卸载环境"
    echo "4) 仅申请/续期SSL证书"
    echo "5) 自定义网站搭建(输入_可跳过SSL配置)"
    echo "0) 退出脚本"
    read -e -p "请输入选项数字 [1/2/3/4/5/0]: " user_choice

    case "$user_choice" in
        4)
            echo "仅申请/续期SSL证书..."
            apply_ssl_cert || {
                echo "SSL证书申请失败，请检查网络或手动申请。"
            }
            ;;
        3)
            uninstall_env
            echo ""
            continue
            ;;
        2)
            install_typecho
            ;;
        1)  
            if [ -d "$INSTALL_DIR" ]; then
                echo "检测到Typecho已安装，请先卸载环境或删除Typecho目录：$INSTALL_DIR"
                continue
            fi
            echo "检测到Typecho未安装，准备安装环境..."
            stty sane
            echo "正在安装网站环境（MySQL、Nginx、PHP等）..."
            DB_ROOT_PASS="$(openssl rand -base64 12)"

            echo "修复系统依赖..."
            apt update
            apt install -y gnupg lsb-release ca-certificates apt-transport-https

            echo "清理可能存在的旧MySQL安装..."
            read -p "确定要清理旧MySQL安装吗？这将删除所有MySQL数据 (y/n): " confirm
            if [[ "$confirm" != "y" ]]; then
                echo "已取消清理旧MySQL安装"
                return 1
            fi
            
            echo "停止MySQL/MariaDB服务..."
            systemctl stop mysql mariadb 2>/dev/null || echo "服务停止失败(可能未安装)"
            
            echo "卸载MySQL/MariaDB软件包..."
            apt purge -y mysql-server mysql-client mysql-common mariadb-server mariadb-client
            apt autoremove -y
            
            echo "删除残留文件和目录..."
            rm -rf /etc/mysql /var/lib/mysql 2>/dev/null

            echo "重新安装MariaDB..."
            apt install -y mariadb-server mariadb-client

            if [ ! -f /usr/bin/mariadb ] && [ -f /usr/bin/mysql ]; then
                ln -s /usr/bin/mysql /usr/bin/mariadb
            fi

            echo "执行MariaDB安全设置..."
            systemctl restart mariadb

            # 设置本地 root 密码
            mariadb -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';"

            # 清理无用用户和测试库
            mariadb -uroot -p"$DB_ROOT_PASS" -e "DELETE FROM mysql.user WHERE User='';"
            mariadb -uroot -p"$DB_ROOT_PASS" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
            mariadb -uroot -p"$DB_ROOT_PASS" -e "DROP DATABASE IF EXISTS test;"
            mariadb -uroot -p"$DB_ROOT_PASS" -e "FLUSH PRIVILEGES;"

            # 允许root远程登录（先创建再授权，避免报错）
            mariadb -uroot -p"$DB_ROOT_PASS" -e "CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY '$DB_ROOT_PASS';"
            mariadb -uroot -p"$DB_ROOT_PASS" -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;"
            mariadb -uroot -p"$DB_ROOT_PASS" -e "FLUSH PRIVILEGES;"

            # 修改配置文件允许远程连接
            sed -i 's/^bind-address\s*=.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf
            systemctl restart mariadb

            echo "正在安装Nginx最新版..."
            rm -f /etc/apt/sources.list.d/nginx.list
            apt install -y gnupg
            curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
            echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/debian bookworm nginx" > /etc/apt/sources.list.d/nginx.list
            echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" > /etc/apt/preferences.d/99nginx
            apt update
            apt install -y nginx

            echo "正在安装PHP 8.3..."
            rm -f /etc/apt/sources.list.d/php.list
            curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
            echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ bookworm main" > /etc/apt/sources.list.d/php.list
            apt update
            apt install -y php8.3-fpm php8.3-cli php8.3-mysql php8.3-curl php8.3-mbstring php8.3-xml php8.3-gd libargon2-1

            if [ -f /etc/php/8.3/fpm/pool.d/www.conf ]; then
                sed -i 's/^listen = .*/listen = 127.0.0.1:9000/' /etc/php/8.3/fpm/pool.d/www.conf
            fi
            systemctl restart php8.3-fpm

            echo "网站环境安装完成！"
            echo "MySQL 数据库信息："
            echo "  用户名: root"
            echo "  密码: $DB_ROOT_PASS"
            echo "请妥善保存以上信息，后续安装Typecho时需要用到。"
            ;;
        5)
            echo "自定义网站搭建..."
            setup_custom_site || {
                echo "自定义网站配置失败，请检查输入参数。"
            }
            ;;
        0)
            echo "感谢你的使用，制作人：桦哲"
            echo "已退出。"
            exit 0
            ;;
        *)
            echo "无效选项，请重新输入。"
            ;;
    esac
    echo ""
done