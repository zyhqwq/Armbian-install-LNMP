#!/bin/bash

# Debian 12 安装 Typecho 一键脚本（MariaDB修复版）

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root用户运行此脚本！"
    exit 1
fi

# 设置变量
DB_ROOT_PASS="$(openssl rand -base64 12)"
INSTALL_DIR="/var/www/typecho"

# 1. 修复系统依赖
echo "修复系统依赖..."
apt update
apt --fix-broken install -y
apt install -y curl wget unzip expect openssl

# 2. 完全清理旧MariaDB安装（如果有）
echo "清理可能存在的旧MariaDB安装..."
systemctl stop mariadb 2>/dev/null
apt purge -y mariadb-* mysql-*
rm -rf /etc/mysql /var/lib/mysql
apt autoremove -y

# 3. 重新安装MariaDB（完整安装）
echo "重新安装MariaDB..."
apt install -y mariadb-server mariadb-client

# 4. 手动创建缺失的配置文件
echo "修复MariaDB配置文件..."
mkdir -p /etc/mysql/conf.d/
if [ ! -f "/etc/mysql/mariadb.cnf" ]; then
    cat > /etc/mysql/mariadb.cnf <<EOF
[client]
port = 3306
socket = /var/run/mysqld/mysqld.sock

[mysqld]
user = mysql
pid-file = /var/run/mysqld/mysqld.pid
socket = /var/run/mysqld/mysqld.sock
port = 3306
basedir = /usr
datadir = /var/lib/mysql
tmpdir = /tmp
lc-messages-dir = /usr/share/mysql
EOF
fi

# 5. 手动执行安全设置（替代mysql_secure_installation）
echo "执行MariaDB安全设置..."
systemctl restart mariadb
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';"
mysql -uroot -p"${DB_ROOT_PASS}" -e "DELETE FROM mysql.user WHERE User='';"
mysql -uroot -p"${DB_ROOT_PASS}" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -uroot -p"${DB_ROOT_PASS}" -e "DROP DATABASE IF EXISTS test;"
mysql -uroot -p"${DB_ROOT_PASS}" -e "FLUSH PRIVILEGES;"

# 6. 设置Typecho数据库
echo "设置Typecho数据库..."
read -p "请输入Typecho数据库密码: " db_password
mysql -uroot -p"${DB_ROOT_PASS}" -e "CREATE DATABASE IF NOT EXISTS typecho;"
mysql -uroot -p"${DB_ROOT_PASS}" -e "CREATE USER IF NOT EXISTS 'typecho'@'localhost' IDENTIFIED BY '${db_password}';"
mysql -uroot -p"${DB_ROOT_PASS}" -e "GRANT ALL PRIVILEGES ON typecho.* TO 'typecho'@'localhost';"
mysql -uroot -p"${DB_ROOT_PASS}" -e "FLUSH PRIVILEGES;"

# 安装Nginx
echo "正在安装Nginx最新版..."
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/debian $(lsb_release -cs) nginx" | tee /etc/apt/sources.list.d/nginx.list
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx
apt update
apt install -y nginx

# 安装PHP 8.3
echo "正在安装PHP 8.3..."
curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
apt update
apt install -y php8.3-fpm php8.3-cli php8.3-mysql php8.3-curl php8.3-mbstring php8.3-xml php8.3-gd

# 配置PHP-FPM
sed -i 's/^listen = .*/listen = 127.0.0.1:9000/' /etc/php/8.3/fpm/pool.d/www.conf
systemctl restart php8.3-fpm

# 安装Typecho
echo "正在安装Typecho..."
wget --no-check-certificate https://github.zyhmifan.top/github.com/typecho/typecho/releases/download/v1.2.1/typecho.zip -O typecho.zip || {
    echo "下载Typecho失败，请检查网络连接"
    exit 1
}
mkdir -p ${INSTALL_DIR}
unzip -o typecho.zip -d ${INSTALL_DIR} || {
    echo "解压Typecho失败，请检查zip文件是否完整"
    exit 1
}
chown -R www-data:www-data ${INSTALL_DIR}
find ${INSTALL_DIR} -type d -exec chmod 755 {} \;
find ${INSTALL_DIR} -type f -exec chmod 644 {} \;

# SSL证书配置选择
read -p "是否要配置SSL证书？(y/n): " ssl_choice
if [[ "$ssl_choice" =~ ^[Yy]$ ]]; then
    echo "准备申请SSL证书..."
    # 域名输入校验
    while true; do
        read -p "请输入您的域名(如example.com): " domain_name
        if [[ "$domain_name" =~ ^[a-zA-Z0-9.-]+$ && ! "$domain_name" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            break
        else
            echo "错误：域名格式无效，请输入有效域名(不要包含http/https)"
        fi
    done
    read -p "请输入您的域名(如example.com): " domain_name
    read -p "请输入您的邮箱: " email_address

    mkdir -p /etc/nginx/ssl/
    apt install -y socat cron
    curl https://get.acme.sh | sh -s email=${email_address}
    source ~/.bashrc
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue --standalone -d ${domain_name} -d www.${domain_name} -k ec-256 || {
        echo "SSL证书申请失败，请检查域名解析和80端口是否开放"
        exit 1
    }
    ~/.acme.sh/acme.sh --installcert -d ${domain_name} --ecc \
        --fullchain-file /etc/nginx/ssl/${domain_name}.crt \
        --key-file /etc/nginx/ssl/${domain_name}.key

    # 生成带SSL的Nginx配置
    cat > /etc/nginx/conf.d/typecho.conf <<EOF
server {
    listen 80;
    server_name ${domain_name} www.${domain_name};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${domain_name} www.${domain_name};
    
    ssl_certificate /etc/nginx/ssl/${domain_name}.crt;
    ssl_certificate_key /etc/nginx/ssl/${domain_name}.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    root ${INSTALL_DIR};
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
    # IP/域名输入校验
    while true; do
        read -p "请输入您的域名或IP地址: " domain_name
        # IP地址校验正则 (0-255.0-255.0-255.0-255)
        if [[ "$domain_name" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            IFS='.' read -ra ip_parts <<< "$domain_name"
            valid_ip=1
            for part in "${ip_parts[@]}"; do
                if ((part < 0 || part > 255)); then
                    valid_ip=0
                    break
                fi
            done
            ((valid_ip)) && break || echo "错误：IP地址无效，各段应在0-255之间"
        elif [[ "$domain_name" =~ ^[a-zA-Z0-9.-]+$ ]]; then
            break
        else
            echo "错误：输入格式无效，请输入有效IP或域名"
        fi
    done
    # 生成不带SSL的Nginx配置
    cat > /etc/nginx/conf.d/typecho.conf <<EOF
server {
    listen 80;
    server_name ${domain_name};
    
    root ${INSTALL_DIR};
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
fi

# 测试Nginx配置
nginx -t || {
    echo "Nginx配置测试失败，请检查配置文件"
    exit 1
}

# 重启服务
systemctl restart nginx
systemctl restart php8.3-fpm

# ================== 新增验证步骤 ==================
# 创建测试文件
TEST_FILE="${INSTALL_DIR}/php_test_$(date +%s).php"
echo "<?php echo 'VALIDATION_SUCCESS'; ?>" > ${TEST_FILE}
chown www-data:www-data ${TEST_FILE}

# 执行验证检测
echo -e "\n正在进行安装验证..."
VALID_URL="http://${domain_name}/$(basename ${TEST_FILE})"
if curl -s --connect-timeout 10 ${VALID_URL} | grep -q "VALIDATION_SUCCESS"; then
    echo "✅ PHP解析验证成功"
else
    echo "❌ PHP解析验证失败，请检查："
    echo "1. 确保已通过 http://${domain_name} 访问"
    echo "2. 检查防火墙设置"
    echo "3. 查看错误日志：tail -n 50 /var/log/nginx/error.log"
fi

# 清理测试文件
rm -f ${TEST_FILE}
# ================== 验证步骤结束 ==================

# 显示安装结果
echo "=============================================="
echo "✅ Typecho 安装完成！"
if [[ "$ssl_choice" =~ ^[Yy]$ ]]; then
    echo "访问地址: https://${domain_name}"
else
    echo "访问地址: http://${domain_name}"
fi
echo "MariaDB root密码: ${DB_ROOT_PASS}"
echo "Typecho数据库信息:"
echo "  数据库名: typecho"
echo "  用户名: typecho"
echo "  密码: ${db_password}"
echo ""
echo "请立即记录以上密码信息！"
echo "=============================================="
echo "感谢你的使用，制作人：桦哲"

# 清理临时文件
rm -f typecho.zip