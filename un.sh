#!/bin/bash

# Debian 12 Typecho 完全卸载脚本
# 适用于基于修复版安装脚本的完整卸载

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root用户运行此脚本！"
    exit 1
fi

# 确认操作
read -p "⚠️  这将完全卸载Typecho及相关组件(MariaDB/Nginx/PHP/SSL证书)，确定继续吗？[y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "卸载已取消。"
    exit 0
fi

# 获取安装信息
read -p "请输入安装时使用的域名，没有则回车(用于清理SSL证书): " domain_name
read -p "请输入MariaDB root密码: " db_root_pass

# 停止服务
echo "正在停止相关服务..."
systemctl stop nginx 2>/dev/null
systemctl stop php8.3-fpm 2>/dev/null
systemctl stop mariadb 2>/dev/null

# 1. 删除Typecho程序文件
echo "正在删除Typecho文件..."
INSTALL_DIR="/var/www/typecho"
rm -rf "$INSTALL_DIR" 2>/dev/null
rm -f /root/typecho.zip 2>/dev/null

# 2. 清理数据库
echo "正在删除数据库..."
mysql -uroot -p"${db_root_pass}" -e "DROP DATABASE IF EXISTS typecho;" 2>/dev/null
mysql -uroot -p"${db_root_pass}" -e "DROP USER IF EXISTS 'typecho'@'localhost';" 2>/dev/null
mysql -uroot -p"${db_root_pass}" -e "FLUSH PRIVILEGES;" 2>/dev/null

# 3. 删除Nginx配置
echo "正在清理Nginx配置..."
rm -f /etc/nginx/conf.d/typecho.conf 2>/dev/null
rm -f /etc/nginx/ssl/${domain_name}.crt 2>/dev/null
rm -f /etc/nginx/ssl/${domain_name}.key 2>/dev/null
[ -d "/etc/nginx/ssl" ] && rmdir /etc/nginx/ssl 2>/dev/null

# 4. 卸载软件包
echo "正在卸载软件包..."
apt purge -y \
    nginx \
    php8.3* \
    mariadb-server \
    mariadb-client \
    mariadb-common \
    galera-4 \
    libnuma1 \
    liburing2 \
    rsync \
    socat 2>/dev/null

apt autoremove -y 2>/dev/null

# 5. 清理软件源
echo "正在移除软件源配置..."
rm -f /etc/apt/sources.list.d/nginx.list 2>/dev/null
rm -f /etc/apt/sources.list.d/php.list 2>/dev/null
rm -f /etc/apt/preferences.d/99nginx 2>/dev/null
rm -f /usr/share/keyrings/nginx-archive-keyring.gpg 2>/dev/null
rm -f /usr/share/keyrings/deb.sury.org-php.gpg 2>/dev/null

# 6. 清理MariaDB残留
echo "正在清理MariaDB数据..."
rm -rf /etc/mysql 2>/dev/null
rm -rf /var/lib/mysql 2>/dev/null

# 7. 清理PHP残留
echo "正在清理PHP配置..."
rm -rf /etc/php 2>/dev/null

# 8. 清理acme.sh
echo "正在删除SSL证书工具..."
[ -d ~/.acme.sh ] && ~/.acme.sh/acme.sh --uninstall
rm -rf ~/.acme.sh 2>/dev/null

# 9. 清理定时任务
echo "正在清理证书续期任务..."
crontab -l | grep -v 'acme.sh' | crontab - 2>/dev/null

# 10. 恢复系统配置
echo "正在恢复系统服务..."
systemctl daemon-reload

# 清理临时文件
echo "正在清理临时文件..."
rm -rf /tmp/typecho* 2>/dev/null
rm -f /var/log/nginx/typecho* 2>/dev/null

echo "=============================================="
echo "✅ Typecho 已完全卸载！"
echo "已删除以下内容："
echo "1. Typecho程序文件 (${INSTALL_DIR})"
echo "2. MariaDB数据库和用户"
echo "3. Nginx配置和SSL证书"
echo "4. PHP 8.3和相关扩展"
echo "5. 所有相关软件包和依赖"
echo "6. 自动证书续期配置"
echo "=============================================="
echo "建议操作："
echo "1. 运行 apt update 更新软件源"
echo "2. 重启系统以确保完全清理"
echo "感谢你的使用，制作人：桦哲"