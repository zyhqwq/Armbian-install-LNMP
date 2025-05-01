#!/bin/bash
# Typecho 终极一键安装脚本 v2.0
# 支持：Debian/Ubuntu + Nginx + PHP 8.3 + MySQL/MariaDB/SQLite
# 功能：纯净安装 | 彻底卸载 | 故障修复 | 安全加固

# 严格模式
set -euo pipefail
IFS=$'\n\t'

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

# 初始化配置
readonly WEB_ROOT="/var/www/typecho"
readonly PHP_VERSION="8.3"
readonly PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
readonly MIRRORS=(
    "https://github.zyhmifan.top/https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
    "https://ghproxy.net/https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
    "https://gitproxy.click/https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
    "https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
)

# --------------------------
# 功能函数
# --------------------------

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：必须使用root用户运行此脚本！${RESET}"
        exit 1
    fi
}

# 显示菜单
show_menu() {
    clear
    echo -e "${GREEN}"
    echo "========================================"
    echo " Typecho 终极管理脚本 v2.0"
    echo "========================================"
    echo -e "${RESET}"
    echo -e "${BLUE}请选择操作：${RESET}"
    echo "1) 全新安装 Typecho"
    echo "2) 完全卸载 Typecho"
    echo "3) 修复常见问题"
    echo "4) 安全加固配置"
    echo -e "${RED}5) 退出脚本${RESET}"
    echo -e "${YELLOW}请输入数字选择 (1-5):${RESET} "
}

# 环境清理
clean_environment() {
    echo -e "${YELLOW}[环境净化] 清理残留配置...${RESET}"
    
    # 创建备份目录
    local backup_dir="/var/backups/typecho_$(date +%Y%m%d%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 备份重要文件
    find "${WEB_ROOT}" -maxdepth 1 -type f \( -name "config.inc.php" -o -name ".user.ini" \) -exec cp {} "$backup_dir" \; 2>/dev/null || true
    
    # 备份数据库
    if [ -d "${WEB_ROOT}/usr" ]; then
        cp -r "${WEB_ROOT}/usr" "$backup_dir"
    fi
    
    echo -e "${GREEN}已备份旧数据到：${BLUE}${backup_dir}${RESET}"
    
    # 清理安装目录（保留隐藏文件）
    find "${WEB_ROOT}" -mindepth 1 -maxdepth 1 ! -name '.*' -exec rm -rf {} +
}

# 下载安装包
download_typecho() {
    echo -e "${YELLOW}[1/6] 正在下载 Typecho...${RESET}"
    
    local temp_file=$(mktemp)
    local downloaded=false
    
    for mirror in "${MIRRORS[@]}"; do
        echo -e "尝试镜像：${BLUE}${mirror}${RESET}"
        if wget --no-check-certificate --timeout=20 --tries=3 -O "$temp_file" "$mirror"; then
            if unzip -tq "$temp_file" >/dev/null; then
                downloaded=true
                mv "$temp_file" /tmp/typecho.zip
                echo -e "${GREEN}✓ 下载成功${RESET}"
                break
            else
                echo -e "${YELLOW}警告：下载文件校验失败，尝试下一个镜像...${RESET}"
            fi
        else
            echo -e "${YELLOW}✗ 当前镜像不可用${RESET}"
        fi
    done
    
    rm -f "$temp_file"
    
    if [ "$downloaded" = false ]; then
        echo -e "${RED}错误：所有镜像下载失败，请检查网络连接！${RESET}"
        exit 1
    fi
}

# 部署文件
deploy_files() {
    echo -e "${YELLOW}[2/6] 部署文件中...${RESET}"
    
    # 使用临时目录解压
    local temp_dir=$(mktemp -d)
    unzip -q /tmp/typecho.zip -d "$temp_dir"
    
    # 处理不同压缩包结构
    if [ -d "$temp_dir/build" ]; then
        mv "$temp_dir/build"/* "${WEB_ROOT}"
    else
        mv "$temp_dir"/* "${WEB_ROOT}"
    fi
    
    # 清理临时文件
    rm -rf "$temp_dir"
    
    # 创建必要目录
    mkdir -p "${WEB_ROOT}/usr/uploads"
    chmod 750 "${WEB_ROOT}/usr/uploads"
}

# 设置权限
set_permissions() {
    echo -e "${YELLOW}[3/6] 设置权限...${RESET}"
    
    # 基础权限
    find "${WEB_ROOT}" -type d -exec chmod 750 {} \;
    find "${WEB_ROOT}" -type f -exec chmod 640 {} \;
    
    # 特殊权限
    chmod 750 "${WEB_ROOT}/index.php"
    chmod 750 "${WEB_ROOT}/install.php"
    
    # 所有权设置
    chown -R www-data:www-data "${WEB_ROOT}"
    
    # 保护配置文件
    chmod 440 "${WEB_ROOT}/config.inc.php" 2>/dev/null || true
}

# 数据库配置
configure_database() {
    echo -e "${YELLOW}[4/6] 数据库配置...${RESET}"
    
    echo -e "${BLUE}请选择数据库类型：${RESET}"
    select DB_TYPE in "MySQL/MariaDB" "SQLite"; do
        case $DB_TYPE in
            "MySQL/MariaDB")
                configure_mysql
                break
                ;;
            SQLite)
                configure_sqlite
                break
                ;;
        esac
    done
}

configure_mysql() {
    # 检查是否已安装
    if ! command -v mysql &>/dev/null; then
        echo -e "${YELLOW}正在安装MySQL/MariaDB...${RESET}"
        apt install -y mariadb-server
        mysql_secure_installation
    fi
    
    # 生成随机密码
    local db_pass=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    local root_pass=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
    
    # 设置root密码（如果未设置）
    if ! mysql -uroot -e "SELECT 1" &>/dev/null; then
        mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_pass}';"
    fi
    
    # 创建数据库和用户
    mysql -uroot -p"${root_pass}" -e "CREATE DATABASE IF NOT EXISTS typecho DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -uroot -p"${root_pass}" -e "CREATE USER IF NOT EXISTS 'typecho'@'localhost' IDENTIFIED BY '${db_pass}';"
    mysql -uroot -p"${root_pass}" -e "GRANT ALL PRIVILEGES ON typecho.* TO 'typecho'@'localhost';"
    mysql -uroot -p"${root_pass}" -e "FLUSH PRIVILEGES;"
    
    echo -e "${GREEN}数据库配置完成！${RESET}"
    echo -e "数据库名：${YELLOW}typecho${RESET}"
    echo -e "用户名：${YELLOW}typecho${RESET}"
    echo -e "密码：${YELLOW}${db_pass}${RESET}"
    echo -e "Root密码：${YELLOW}${root_pass}${RESET}"
}

configure_sqlite() {
    # 确保目录存在
    mkdir -p "${WEB_ROOT}/usr"
    
    # 设置权限
    chown www-data:www-data "${WEB_ROOT}/usr"
    chmod 750 "${WEB_ROOT}/usr"
    
    echo -e "${GREEN}SQLite 数据库目录已创建${RESET}"
}

# 配置Nginx
configure_nginx() {
    echo -e "${YELLOW}[5/6] 生成Nginx配置...${RESET}"
    
    # 安装Nginx（如果未安装）
    if ! command -v nginx &>/dev/null; then
        apt install -y nginx
    fi
    
    # 创建优化的Nginx配置
    cat > /etc/nginx/sites-available/typecho <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    root ${WEB_ROOT};
    index index.php;
    
    # 安全增强
    server_tokens off;
    client_max_body_size 64M;
    keepalive_timeout 60s;
    
    # 安全头
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; frame-ancestors 'self'; form-action 'self';" always;
    
    # 主location块
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }
    
    # PHP处理
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/${PHP_FPM_SERVICE}.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
        
        # 关键头传递
        fastcgi_param HTTP_HOST \$host;
        fastcgi_param HTTPS \$scheme if_not_empty;
    }
    
    # 静态文件缓存
    location ~* \.(ico|css|js|gif|jpe?g|png|svg|webp|woff2?)\$ {
        expires 365d;
        add_header Cache-Control "public, no-transform";
        access_log off;
        log_not_found off;
    }
    
    # 保护敏感文件
    location ~ /(\.|config\.inc\.php|composer\.lock|\.ht) {
        deny all;
        return 404;
    }
    
    # 伪静态规则
    if (!-e \$request_filename) {
        rewrite ^/(.*)\$ /index.php/\$1 last;
    }
}
EOF

    # 启用配置
    ln -sf /etc/nginx/sites-available/typecho /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # 测试配置
    if ! nginx -t; then
        echo -e "${RED}Nginx 配置错误，请检查！${RESET}"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}[0/6] 安装系统依赖...${RESET}"
    
    # 添加Sury PHP仓库
    if ! grep -q "packages.sury.org" /etc/apt/sources.list.d/*; then
        echo -e "${BLUE}添加Sury PHP仓库...${RESET}"
        apt install -y apt-transport-https lsb-release ca-certificates curl
        curl -sSL https://packages.sury.org/php/apt.gpg | gpg --dearmor -o /usr/share/keyrings/sury-php-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/sury-php-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/sury-php.list
    fi
    
    # 更新并安装
    apt update
    apt install -y \
        nginx \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-sqlite3 \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-opcache \
        php${PHP_VERSION}-intl \
        unzip \
        wget \
        curl
}

# 安全加固
secure_installation() {
    echo -e "${YELLOW}[安全加固] 正在加固系统...${RESET}"
    
    # 1. 文件权限加固
    chmod 750 "${WEB_ROOT}/admin"
    chmod 640 "${WEB_ROOT}/config.inc.php" 2>/dev/null || true
    
    # 2. 禁用危险函数
    local php_ini=$(php${PHP_VERSION} --ini | grep "Loaded Configuration File" | awk '{print $4}')
    sed -i 's/^disable_functions =.*/disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source/' "$php_ini"
    
    # 3. 限制PHP访问
    echo "open_basedir = ${WEB_ROOT}:/tmp" >> "$php_ini"
    
    # 4. 防火墙规则
    if command -v ufw &>/dev/null; then
        ufw allow 'Nginx Full'
        ufw --force enable
    fi
    
    # 5. 重启服务
    systemctl restart ${PHP_FPM_SERVICE}
    
    echo -e "${GREEN}安全加固完成！${RESET}"
}

# 安装主流程
install() {
    check_root
    
    # 显示标题
    clear
    echo -e "${GREEN}"
    echo "========================================"
    echo " Typecho 终极安装向导 v2.0"
    echo "========================================"
    echo -e "${RESET}"
    
    # 确认操作
    read -p "这将安装全新 Typecho 并清除旧数据，确认继续？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[yY] ]]; then
        echo -e "${YELLOW}安装已取消${RESET}"
        exit 0
    fi
    
    # 环境准备
    mkdir -p "${WEB_ROOT}"
    clean_environment
    install_dependencies
    
    # 核心流程
    download_typecho
    deploy_files
    set_permissions
    configure_database
    configure_nginx
    
    # 重启服务
    echo -e "${YELLOW}[6/6] 启动服务...${RESET}"
    systemctl restart nginx ${PHP_FPM_SERVICE}
    rm -f /tmp/typecho.zip
    
    # 完成提示
    local ip_address=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}"
    echo "========================================"
    echo " 安装成功！"
    echo -e " 访问地址：${BLUE}http://${ip_address}/install.php${RESET}"
    echo "========================================"
    echo -e "${RESET}"
}

# 完全卸载
uninstall() {
    check_root
    
    echo -e "${RED}"
    echo "========================================"
    echo " 警告：即将完全卸载 Typecho 环境！"
    echo "========================================"
    echo -e "${RESET}"
    
    read -p "确定要删除所有配置和安装的软件吗？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[yY] ]]; then
        echo -e "${YELLOW}已取消卸载操作${RESET}"
        exit 0
    fi

    echo -e "${YELLOW}[1/4] 停止服务...${RESET}"
    systemctl stop nginx ${PHP_FPM_SERVICE} mysql 2>/dev/null || true

    echo -e "${YELLOW}[2/4] 卸载软件...${RESET}"
    apt purge -y nginx "php${PHP_VERSION}*" mariadb-server 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true

    echo -e "${YELLOW}[3/4] 删除配置...${RESET}"
    rm -rf /etc/nginx /etc/php /etc/mysql 2>/dev/null || true
    rm -rf "${WEB_ROOT}" /tmp/typecho.zip 2>/dev/null || true

    echo -e "${YELLOW}[4/4] 清理残留...${RESET}"
    find /var/www -type d -exec chmod 755 {} \; 2>/dev/null || true
    find /var/www -type f -exec chmod 644 {} \; 2>/dev/null || true

    echo -e "${GREEN}"
    echo "========================================"
    echo " 已彻底移除以下组件："
    echo " ✔ Nginx 服务器"
    echo " ✔ PHP ${PHP_VERSION} 环境"
    echo " ✔ MySQL/MariaDB 数据库"
    echo " ✔ Typecho 程序文件"
    echo "========================================"
    echo -e "${RESET}"
}

# 修复功能
fix_issues() {
    check_root
    
    echo -e "${YELLOW}"
    echo "========================================"
    echo " Typecho 常见问题修复"
    echo "========================================"
    echo -e "${RESET}"
    
    echo -e "${BLUE}请选择修复选项：${RESET}"
    select fix_option in "修复评论功能" "修复文件权限" "重置管理员密码" "返回主菜单"; do
        case $fix_option in
            "修复评论功能")
                fix_comments
                break
                ;;
            "修复文件权限")
                fix_permissions
                break
                ;;
            "重置管理员密码")
                reset_password
                break
                ;;
            "返回主菜单")
                return
                ;;
        esac
    done
}

fix_comments() {
    echo -e "${YELLOW}[评论修复] 正在处理...${RESET}"
    
    # 检查Nginx配置
    if ! grep -q "fastcgi_param HTTP_HOST" /etc/nginx/sites-available/typecho; then
        echo -e "${RED}检测到配置缺失，正在修复...${RESET}"
        sed -i '/fastcgi_param SCRIPT_FILENAME/a \        fastcgi_param HTTP_HOST $host;\n        fastcgi_param HTTPS $scheme if_not_empty;' /etc/nginx/sites-available/typecho
        nginx -t && systemctl restart nginx
    fi
    
    # 清理缓存
    rm -rf "${WEB_ROOT}/usr/cache/*" 2>/dev/null || true
    
    # 重启服务
    systemctl restart nginx ${PHP_FPM_SERVICE}
    
    echo -e "${GREEN}评论功能修复完成！${RESET}"
}

fix_permissions() {
    echo -e "${YELLOW}[权限修复] 正在处理...${RESET}"
    
    # 重置权限
    find "${WEB_ROOT}" -type d -exec chmod 750 {} \;
    find "${WEB_ROOT}" -type f -exec chmod 640 {} \;
    
    # 特殊权限
    chmod 750 "${WEB_ROOT}/index.php"
    chmod 750 "${WEB_ROOT}/install.php"
    
    # 所有权设置
    chown -R www-data:www-data "${WEB_ROOT}"
    
    echo -e "${GREEN}文件权限修复完成！${RESET}"
}

reset_password() {
    echo -e "${YELLOW}[密码重置] 正在处理...${RESET}"
    
    if [ ! -f "${WEB_ROOT}/config.inc.php" ]; then
        echo -e "${RED}错误：未找到Typecho配置文件！${RESET}"
        return
    fi
    
    # 提取数据库配置
    local db_config=$(grep -A 6 "'db' =>" "${WEB_ROOT}/config.inc.php")
    local db_type=$(echo "$db_config" | grep "'type'" | cut -d "'" -f 4)
    
    if [ "$db_type" == "mysql" ]; then
        reset_mysql_password
    elif [ "$db_type" == "sqlite" ]; then
        reset_sqlite_password
    else
        echo -e "${RED}错误：不支持的数据库类型！${RESET}"
    fi
}

reset_mysql_password() {
    local db_host=$(echo "$db_config" | grep "'host'" | cut -d "'" -f 4)
    local db_user=$(echo "$db_config" | grep "'user'" | cut -d "'" -f 4)
    local db_pass=$(echo "$db_config" | grep "'password'" | cut -d "'" -f 4)
    local db_name=$(echo "$db_config" | grep "'database'" | cut -d "'" -f 4)
    
    # 生成新密码
    local new_pass=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
    local encrypted_pass=$(php -r "echo password_hash('${new_pass}', PASSWORD_BCRYPT);")
    
    # 更新数据库
    mysql -h "$db_host" -u "$db_user" -p"$db_pass" "$db_name" -e \
        "UPDATE typecho_users SET password='${encrypted_pass}' WHERE uid=1;"
    
    echo -e "${GREEN}管理员密码已重置！${RESET}"
    echo -e "新密码：${YELLOW}${new_pass}${RESET}"
}

reset_sqlite_password() {
    local db_file=$(echo "$db_config" | grep "'file'" | cut -d "'" -f 4)
    local new_pass=$(openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
    local encrypted_pass=$(php -r "echo password_hash('${new_pass}', PASSWORD_BCRYPT);")
    
    # 使用SQLite3更新
    sqlite3 "${WEB_ROOT}/${db_file}" \
        "UPDATE typecho_users SET password='${encrypted_pass}' WHERE uid=1;"
    
    echo -e "${GREEN}管理员密码已重置！${RESET}"
    echo -e "新密码：${YELLOW}${new_pass}${RESET}"
}

# --------------------------
# 主程序
# --------------------------
while true; do
    show_menu
    read -p "请输入选择：" choice
    case $choice in
        1) install ;;
        2) uninstall ;;
        3) fix_issues ;;
        4) secure_installation ;;
        5) exit 0 ;;
        *) echo -e "${RED}无效输入，请重新选择！${RESET}" ;;
    esac
    read -p "按回车键继续..."
done
