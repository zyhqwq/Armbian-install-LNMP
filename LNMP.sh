#!/bin/bash
# Typecho 终极一键安装脚本
# 支持：Armbian/Ubuntu + Nginx + PHP 8.3 + MySQL/SQLite
# 功能：纯净安装 | 彻底卸载 | 故障修复

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

# 初始化配置
WEB_ROOT="/var/www/typecho"
PHP_VERSION="8.3"
PHP_FPM_SERVICE="php${PHP_VERSION}-fpm"
MIRRORS=(
    "https://github.zyhmifan.top/https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
    "https://ghproxy.net/https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
    "https://gitproxy.click/https://github.com/typecho/typecho/releases/latest/download/typecho.zip"
)

# 强制错误退出
set -eo pipefail

# --------------------------
# 功能函数
# --------------------------

# 显示菜单
show_menu() {
    clear
    echo -e "${GREEN}"
    echo "========================================"
    echo " Typecho 终极管理脚本"
    echo "========================================"
    echo -e "${RESET}"
    echo -e "${BLUE}请选择操作：${RESET}"
    echo "1) 全新安装 Typecho"
    echo "2) 完全卸载 Typecho"
    echo "3) 修复评论功能"
    echo -e "${RED}4) 退出脚本${RESET}"
    echo -e "${YELLOW}请输入数字选择 (1-4):${RESET} "
}

# 环境清理
clean_environment() {
    echo -e "${YELLOW}[环境净化] 清理残留配置...${RESET}"
    
    # 删除安装锁文件
    rm -f "${WEB_ROOT}/.installed" 2>/dev/null || true
    
    # 备份旧配置文件
    local backup_dir="/tmp/typecho_backup_$(date +%s)"
    mkdir -p "$backup_dir"
    find "${WEB_ROOT}" -maxdepth 1 -type f \( -name "config.inc.php" -o -name ".user.ini" \) -exec mv {} "$backup_dir" \; 2>/dev/null || true
    
    # 备份数据库目录
    if [ -d "${WEB_ROOT}/usr" ]; then
        mv "${WEB_ROOT}/usr" "${backup_dir}/usr"
    fi
    
    echo -e "${GREEN}已备份旧配置到：${BLUE}${backup_dir}${RESET}"
}

# 下载安装包
download_typecho() {
    echo -e "${YELLOW}[1/6] 正在下载 Typecho...${RESET}"
    
    local downloaded=false
    for mirror in "${MIRRORS[@]}"; do
        echo -e "尝试镜像：${BLUE}${mirror}${RESET}"
        if wget -q --timeout=20 --tries=3 -O /tmp/typecho.zip "$mirror"; then
            downloaded=true
            echo -e "${GREEN}✓ 下载成功${RESET}"
            break
        else
            echo -e "${RED}✗ 当前镜像不可用${RESET}"
        fi
    done
    
    if [ "$downloaded" = false ]; then
        echo -e "${RED}错误：所有镜像下载失败，请检查网络连接！${RESET}"
        exit 1
    fi

    # 验证文件完整性
    if ! unzip -tq /tmp/typecho.zip >/dev/null; then
        echo -e "${RED}错误：安装包损坏，请重新运行脚本！${RESET}"
        exit 1
    fi
}

# 部署文件
deploy_files() {
    echo -e "${YELLOW}[2/6] 部署文件中...${RESET}"
    
    # 清空目录（保留隐藏文件）
    find "${WEB_ROOT}" -mindepth 1 -maxdepth 1 ! -name '.*' -exec rm -rf {} +
    
    # 使用临时目录解压
    local temp_dir=$(mktemp -d)
    unzip -q /tmp/typecho.zip -d "$temp_dir"
    
    # 修正文件结构
    if [ -d "$temp_dir/build" ]; then
        mv "$temp_dir/build"/* "${WEB_ROOT}"
    else
        mv "$temp_dir"/* "${WEB_ROOT}"
    fi
    
    # 清理临时文件
    rm -rf "$temp_dir"
    
    # 修复vendor目录
    if [ -d "${WEB_ROOT}/vendor" ]; then
        chown -R www-data:www-data "${WEB_ROOT}/vendor"
    fi
}

# 设置权限
set_permissions() {
    echo -e "${YELLOW}[3/6] 设置权限...${RESET}"
    
    # 目录权限
    find "${WEB_ROOT}" -type d -exec chmod 755 {} \;
    
    # 文件权限
    find "${WEB_ROOT}" -type f -exec chmod 644 {} \;
    
    # 特殊权限
    chmod 755 "${WEB_ROOT}/index.php"
    chmod 755 "${WEB_ROOT}/install.php"
    
    # 所有权设置
    chown -R www-data:www-data "${WEB_ROOT}"
}

# 数据库配置
configure_database() {
    echo -e "${YELLOW}[4/6] 数据库配置...${RESET}"
    
    echo -e "${BLUE}请选择数据库类型：${RESET}"
    select DB_TYPE in "MySQL" "SQLite"; do
        case $DB_TYPE in
            MySQL)
                # 自动生成安全密码
                MYSQL_PASS=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 12)
                
                # 安装MySQL
                if ! command -v mysql &>/dev/null; then
                    apt install -y mysql-server
                fi
                
                # 安全配置
                mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_PASS}';"
                mysql -uroot -p"${MYSQL_PASS}" -e "CREATE DATABASE typecho DEFAULT CHARACTER SET utf8mb4;"
                mysql -uroot -p"${MYSQL_PASS}" -e "CREATE USER 'typecho'@'localhost' IDENTIFIED BY '${MYSQL_PASS}';"
                mysql -uroot -p"${MYSQL_PASS}" -e "GRANT ALL PRIVILEGES ON typecho.* TO 'typecho'@'localhost';"
                mysql -uroot -p"${MYSQL_PASS}" -e "FLUSH PRIVILEGES;"
                
                echo -e "${GREEN}MySQL 数据库已创建！"
                echo -e "用户名：${YELLOW}typecho"
                echo -e "密码：${YELLOW}${MYSQL_PASS}${RESET}"
                break
                ;;
                
            SQLite)
                mkdir -p "${WEB_ROOT}/usr"
                chown www-data:www-data "${WEB_ROOT}/usr"
                chmod 755 "${WEB_ROOT}/usr"
                echo -e "${GREEN}SQLite 数据库目录已创建${RESET}"
                break
                ;;
        esac
    done
}

# 配置Nginx
configure_nginx() {
    echo -e "${YELLOW}[5/6] 生成Nginx配置...${RESET}"
    
    cat > /etc/nginx/sites-available/typecho <<EOF
server {
    listen 80;
    server_name _;
    root /var/www/typecho;
    index index.php;
    client_max_body_size 64M;

    # 安全增强头（应放在 server 块内，不要嵌套在 location 中）
    add_header X-Content-Type-Options "nosniff";
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";

    # ✅ 唯一的 location / 块
    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    # PHP 处理配置
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;

        # 关键头传递
        fastcgi_param HTTP_HOST $host;
        fastcgi_param HTTPS $scheme;
    }

    # 静态文件优化
    location ~* \.(ico|css|js|gif|jpe?g|png|svg|webp|woff2?)$ {
        expires 365d;
        add_header Cache-Control "public, no-transform";
        access_log off;
    }

    # 保护敏感文件
    location ~ /(\.|config\.inc\.php|composer\.lock) {
        deny all;
    }

    # 伪静态规则
    if (!-e $request_filename) {
        rewrite ^/(.*)$ /index.php/$1 last;
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
    
    apt update
    apt install -y \
        nginx \
        php${PHP_VERSION} \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-sqlite3 \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-opcache \
        unzip \
        wget
}

# 安装主流程
install() {
    # 显示标题
    clear
    echo -e "${GREEN}"
    echo "========================================"
    echo " Typecho 终极安装向导"
    echo "========================================"
    echo -e "${RESET}"
    
    # 确认操作
    read -p "这将安装全新 Typecho 并清除旧数据，确认继续？(y/N): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
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
    echo -e "${GREEN}"
    echo "========================================"
    echo " 安装成功！"
    echo -e " 访问地址：${BLUE}http://$(hostname -I | awk '{print $1}')/install.php${RESET}"
    [[ -n "$MYSQL_PASS" ]] && echo -e " MySQL密码：${YELLOW}${MYSQL_PASS}${RESET}"
    echo "========================================"
    echo -e "${RESET}"
}

# 完全卸载
uninstall() {
    echo -e "${RED}"
    echo "========================================"
    echo " 警告：即将完全卸载 Typecho 环境！"
    echo "========================================"
    echo -e "${RESET}"
    
    read -p "确定要删除所有配置和安装的软件吗？(y/N): " confirm
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        echo -e "${YELLOW}已取消卸载操作${RESET}"
        exit 0
    fi

    echo -e "${YELLOW}[1/4] 停止服务...${RESET}"
    systemctl stop nginx ${PHP_FPM_SERVICE} mysql 2>/dev/null || true

    echo -e "${YELLOW}[2/4] 卸载软件...${RESET}"
    apt purge -y nginx "php${PHP_VERSION}*" mysql-server 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true

    echo -e "${YELLOW}[3/4] 删除配置...${RESET}"
    rm -rf /etc/nginx /etc/php /etc/mysql 2>/dev/null || true
    rm -rf "${WEB_ROOT}" /tmp/typecho.zip 2>/dev/null || true

    echo -e "${YELLOW}[4/4] 重置权限...${RESET}"
    find /var/www -type d -exec chmod 755 {} \; 2>/dev/null || true
    find /var/www -type f -exec chmod 644 {} \; 2>/dev/null || true

    echo -e "${GREEN}"
    echo "========================================"
    echo " 已彻底移除以下组件："
    echo " ✔ Nginx 服务器"
    echo " ✔ PHP ${PHP_VERSION} 环境"
    echo " ✔ MySQL 数据库"
    echo " ✔ Typecho 程序文件"
    echo "========================================"
    echo -e "${RESET}"
}

# 修复评论
fix_comments() {
    echo -e "${YELLOW}[评论修复] 正在处理...${RESET}"
    
    # 检查Nginx配置
    if ! grep -q "fastcgi_param HTTP_HOST" /etc/nginx/sites-available/typecho; then
        echo -e "${RED}检测到配置缺失，正在修复...${RESET}"
        sed -i '/fastcgi_param SCRIPT_FILENAME/a \        fastcgi_param HTTP_HOST $host;\n        fastcgi_param HTTPS $scheme;' /etc/nginx/sites-available/typecho
        nginx -t && systemctl restart nginx
    fi
    
    # 清理缓存
    rm -rf "${WEB_ROOT}/usr/cache/*" 2>/dev/null || true
    
    # 重启服务
    systemctl restart nginx ${PHP_FPM_SERVICE}
    
    echo -e "${GREEN}评论功能修复完成！${RESET}"
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
        3) fix_comments ;;
        4) exit 0 ;;
        *) echo -e "${RED}无效输入，请重新选择！${RESET}" ;;
    esac
    read -p "按回车键继续..."
done
