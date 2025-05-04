#!/bin/bash

# Debian 12 Typecho 完全卸载脚本（精准逆向版）
# 适配安装脚本：Debian 12 安装 Typecho 一键脚本（MariaDB修复版）
# 作者：桦哲 | 修订：deepseek

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root用户运行此脚本！"
    exit 1
fi

# 确认操作
read -p "这将完全卸载Typecho及相关组件（MariaDB/Nginx/PHP 8.3/SSL证书），确定继续吗？[y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "卸载已取消。"
    exit 0
fi

# 获取安装信息
read -p "请输入安装时使用的域名（用于清理SSL证书），若未配置SSL则直接回车: " domain_name

# 停止服务
echo "正在停止相关服务..."
systemctl stop nginx 2>/dev/null
systemctl stop php8.3-fpm 2>/dev/null
systemctl stop mariadb 2>/dev/null

# 1. 删除Typecho程序文件（精准匹配安装路径）
echo "正在删除Typecho文件..."
INSTALL_DIR="/var/www/typecho"
rm -rf "$INSTALL_DIR" 2>/dev/null
rm -f /root/typecho.zip 2>/dev/null

# 2. 强制清理MariaDB（完全逆向安装步骤）
echo "正在强制清理MariaDB..."
apt purge -y mariadb-* mysql-* 2>/dev/null
rm -rf /etc/mysql /var/lib/mysql 2>/dev/null  # 删除所有数据和配置

# 3. 清理Nginx配置（匹配安装时的配置文件名）
echo "正在清理Nginx..."
apt purge -y nginx 2>/dev/null
rm -f /etc/nginx/conf.d/typecho.conf 2>/dev/null
# SSL证书清理（仅当提供域名时）
if [ -n "$domain_name" ]; then
    rm -f /etc/nginx/ssl/${domain_name}.crt 2>/dev/null
    rm -f /etc/nginx/ssl/${domain_name}.key 2>/dev/null
    [ -d "/etc/nginx/ssl" ] && rmdir /etc/nginx/ssl 2>/dev/null
fi

# 4. 卸载PHP 8.3（精准匹配安装包）
echo "正在清理PHP 8.3..."
apt purge -y php8.3* 2>/dev/null
rm -rf /etc/php 2>/dev/null  # 删除所有PHP配置

# 5. 清理软件源（逆向安装时添加的源）
echo "正在移除第三方软件源..."
rm -f /etc/apt/sources.list.d/nginx.list 2>/dev/null
rm -f /etc/apt/sources.list.d/php.list 2>/dev/null
rm -f /etc/apt/preferences.d/99nginx 2>/dev/null
rm -f /usr/share/keyrings/nginx-archive-keyring.gpg 2>/dev/null
rm -f /usr/share/keyrings/deb.sury.org-php.gpg 2>/dev/null

# 6. 清理acme.sh证书工具（匹配安装流程）
echo "正在删除SSL证书工具..."
[ -d ~/.acme.sh ] && ~/.acme.sh/acme.sh --uninstall 2>/dev/null
rm -rf ~/.acme.sh 2>/dev/null
# 清理证书续期定时任务
crontab -l | grep -v 'acme.sh' | crontab - 2>/dev/null

# 7. 清理系统残留
echo "正在清理临时文件和日志..."
rm -rf /tmp/typecho* 2>/dev/null
rm -f /var/log/nginx/error.log 2>/dev/null  # 可根据需要保留日志

# 8. 恢复系统状态
echo "正在更新软件包列表..."
apt autoremove -y 2>/dev/null
apt update  # 恢复默认软件源

echo "=============================================="
echo "? Typecho 已完全卸载！"
echo "已删除以下内容："
echo "1. Typecho程序文件 (${INSTALL_DIR})"
echo "2. MariaDB所有数据库和配置（强制清理）"
echo "3. Nginx及所有相关配置"
echo "4. PHP 8.3和全部扩展"
echo "5. SSL证书及申请工具（acme.sh）"
echo "=============================================="
echo "警告："
echo "- 所有Typecho相关数据已永久删除！"
echo "- MariaDB数据目录被清空，包括非Typecho数据库！"
echo "建议操作："
echo "1. 手动重启系统：reboot"
echo "2. 运行 apt update && apt upgrade 更新系统"
echo "=============================================="