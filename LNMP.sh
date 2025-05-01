#!/bin/bash
# Typecho 终极管理脚本 (PHP 8.3全兼容版)
# 版本: v2.4.1
# 更新: 2024-06-27

# ███████║ 初始化设置
set -e
trap 'echo -e "${RED}脚本中断！正在回滚...${RESET}"; rollback' INT TERM
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

# ███████║ 颜色定义
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[34m'; CYAN='\033[36m'; RESET='\033[0m'

# ███████║ 动态配置
WEB_ROOT="/var/www/typecho"
DB_NAME="typecho_$(date +%s | tail -c 4)"
DB_USER="user_$(openssl rand -hex 3)"
DB_PASS=$(tr -dc 'A-Za-z0-9!#$%&*+' </dev/urandom | head -c 16)
PHP_SOCK=""
DOMAIN="localhost"  # 默认使用localhost，可根据需要修改

# ███████║ 系统检测
detect_system() {
    if [ -f /etc/os-release ]; then
        OS_ID=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')
        OS_VER=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"')
    else
        OS_ID=$(uname -s)
        OS_VER=$(uname -r)
    fi

    if command -v apt &>/dev/null; then
        PM="apt"
    elif command -v yum &>/dev/null; then
        PM="yum"
    elif command -v dnf &>/dev/null; then
        PM="dnf"
    else
        echo -e "${RED}不支持的包管理器！${RESET}"
        exit 1
    fi
}

# ███████║ 安装PHP 8.3
install_php83() {
    echo -e "${YELLOW}[+] 安装PHP 8.3...${RESET}"

    case $PM in
        apt)
            sudo apt install -y software-properties-common
            sudo add-apt-repository ppa:ondrej/php -y
            sudo apt update
            sudo apt install -y php8.3 php8.3-fpm php8.3-mysql php8.3-curl \
                php8.3-xml php8.3-mbstring php8.3-gd php8.3-zip
            PHP_SOCK="/run/php/php8.3-fpm.sock"
            ;;
        yum|dnf)
            sudo $PM install -y epel-release
            sudo $PM install -y https://rpms.remirepo.net/enterprise/remi-release-$(rpm -E %rhel).rpm
            sudo $PM module enable php:remi-8.3 -y
            sudo $PM install -y php83 php83-php-fpm php83-php-mysqlnd \
                php83-php-curl php83-php-xml php83-php-mbstring php83-php-gd
            PHP_SOCK="/var/opt/remi/php83/run/php-fpm/www.sock"
            ;;
    esac
    
    # 确保PHP-FPM服务启动
    systemctl restart php*-fpm 2>/dev/null || systemctl restart php83-php-fpm 2>/dev/null
}

# ███████║ 依赖安装
install_deps() {
    echo -e "${YELLOW}[1/5] 安装依赖...${RESET}"
    $PM update -y
    $PM install -y wget unzip tar curl nginx mariadb-server

    # 优先尝试安装PHP 8.3
    if ! install_php83; then
        echo -e "${YELLOW}[!] 回退到系统默认PHP版本${RESET}"
        case $PM in
            apt)
                for ver in 8.2 8.1 8.0 7.4; do
                    if $PM install -y php${ver}-fpm php${ver}-mysql; then
                        PHP_SOCK="/run/php/php${ver}-fpm.sock"
                        break
                    fi
                done
                ;;
            yum|dnf)
                $PM install -y php-fpm php-mysqlnd
                PHP_SOCK="/run/php-fpm/www.sock"
                ;;
        esac
    fi
}

# ███████║ 数据库配置
setup_db() {
    echo -e "${YELLOW}[2/5] 配置数据库...${RESET}"
    systemctl start mariadb || systemctl start mysql
    
    if [ ! -d "/var/lib/mysql/mysql" ]; then
        mysql_secure_installation <<EOF
n
y
y
y
y
EOF
    fi

    mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
}

# ███████║ 部署Typecho
deploy_typecho() {
    echo -e "${YELLOW}[3/5] 部署Typecho...${RESET}"
    mkdir -p "${WEB_ROOT}"
    cd "${WEB_ROOT}" || exit

    MIRRORS=(
        "https://github.zyhmifan.top/github.com/typecho/typecho/releases/latest/download/typecho.zip"
        "https://typecho.org/downloads/1.2.1/typecho.zip"
        "https://github.zyhmifan.top/github.com/typecho/typecho/releases/latest/download/typecho.zip"
    )

    for url in "${MIRRORS[@]}"; do
        if wget --tries=3 --timeout=30 -O /tmp/typecho.zip "$url"; then
            break
        fi
    done

    unzip -qo /tmp/typecho.zip
    rm -f /tmp/typecho.zip
    
    # 设置正确的权限
    chown -R www-data:www-data "${WEB_ROOT}"
    find "${WEB_ROOT}" -type d -exec chmod 755 {} \;
    find "${WEB_ROOT}" -type f -exec chmod 644 {} \;
}

# ███████║ Web服务配置
setup_web() {
    echo -e "${YELLOW}[4/5] 配置Web服务...${RESET}"
    
    # 创建Nginx配置文件
    cat > /etc/nginx/sites-available/typecho.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root ${WEB_ROOT};
    index index.php;

    access_log /var/log/nginx/typecho.access.log;
    error_log /var/log/nginx/typecho.error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \\.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\\.ht {
        deny all;
    }
}
EOF

    # 启用站点 (Debian/Ubuntu)
    if [ -d "/etc/nginx/sites-enabled" ]; then
        ln -sf /etc/nginx/sites-available/typecho.conf /etc/nginx/sites-enabled/
        rm -f /etc/nginx/sites-enabled/default
    fi

    # 修改PHP配置
    PHP_INI=$(find /etc -name 'php.ini' | head -1)
    if [ -f "$PHP_INI" ]; then
        sed -i 's/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=1/' "$PHP_INI"
        sed -i 's/;date.timezone =/date.timezone = Asia\/Shanghai/' "$PHP_INI"
    fi

    # 修改PHP-FPM配置
    PHP_FPM_CONF=$(find /etc -name 'www.conf' | head -1)
    if [ -f "$PHP_FPM_CONF" ]; then
        sed -i 's/user = .*/user = www-data/' "$PHP_FPM_CONF"
        sed -i 's/group = .*/group = www-data/' "$PHP_FPM_CONF"
    fi

    # 重启服务
    systemctl restart $(basename "$PHP_SOCK" | sed 's/.sock//')
    systemctl restart nginx
}

# ███████║ 卸载功能
uninstall() {
    read -p "确认卸载Typecho？(y/n): " confirm
    [ "$confirm" != "y" ] && return

    services=("nginx" "mariadb" "php*-fpm")
    for svc in "${services[@]}"; do
        systemctl stop "$svc" 2>/dev/null || true
    done

    case $PM in
        apt) apt purge -y nginx* mariadb* php* ;;
        yum|dnf) $PM remove -y nginx mariadb* php* ;;
    esac

    rm -rf "${WEB_ROOT}" /etc/nginx/sites-*/typecho.conf
    rm -f /etc/nginx/conf.d/typecho.conf
}

# ███████║ 回滚函数
rollback() {
    uninstall
    exit 1
}

# ███████║ 安装完成提示
show_success() {
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════╗"
    echo "║         安装成功                  ║"
    echo "╠════════════════════════════════════╣"
    echo "║ 访问地址: http://${DOMAIN}        ║"
    echo "║ 数据库名: ${DB_NAME}              ║"
    echo "║ 用户名: ${DB_USER}                ║"
    echo "║ 密码: ${DB_PASS}                 ║"
    echo "║ 网站根目录: ${WEB_ROOT}           ║"
    echo "╚════════════════════════════════════╝"
    echo -e "${RESET}"
}

# ███████║ 主菜单
main() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════╗"
    echo "║   Typecho 管理脚本         ║"
    echo "╠════════════════════════════╣"
    echo "║ 1) 一键安装                ║"
    echo "║ 2) 完全卸载                ║"
    echo "║ 3) 退出                    ║"
    echo "╚════════════════════════════╝"

    read -p "请选择: " choice
    case $choice in
        1) 
            detect_system
            install_deps
            setup_db
            deploy_typecho
            setup_web
            show_success
            ;;
        2) uninstall ;;
        3) exit 0 ;;
    esac
}

# ███████║ 执行入口
[ "$(id -u)" -ne 0 ] && {
    echo -e "${RED}请使用root用户运行!${RESET}"
    exit 1
}

detect_system
main
