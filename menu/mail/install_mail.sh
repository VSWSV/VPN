#!/bin/bash
clear
orange="\033[38;5;214m"
cyan="\033[1;36m"
green="\033[1;32m"
red="\033[1;31m"
reset="\033[0m"

MAIL_PATH="/root/VPN/MAIL"
RCDIR="$MAIL_PATH/roundcube"

echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "                   ${orange}📦 Roundcube 邮局环境依赖下载安装（纯净版）${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

# 创建目录
mkdir -p "$RCDIR"

# 安装运行所需的依赖
echo -e "  ${green}▶ 正在安装 Roundcube 所需组件...${reset}"
apt update && apt install -y apache2 mariadb-server unzip wget curl php php-mysql php-intl php-common \
php-curl php-gd php-mbstring php-xml php-zip php-bz2 php-imagick php-cli php-sqlite3 php-net-socket \
libapache2-mod-php

# 下载 Roundcube 源码
cd "$MAIL_PATH"
echo -e "  ${green}▶ 正在下载 Roundcube 最新版本...${reset}"
wget -q https://github.com/roundcube/roundcubemail/releases/latest/download/roundcubemail-complete.tar.gz

# 解压源码
echo -e "  ${green}▶ 正在解压安装文件...${reset}"
tar -xf roundcubemail-complete.tar.gz
mv roundcube-* roundcube
rm -f roundcubemail-complete.tar.gz

# 设置文件权限
echo -e "  ${green}▶ 正在设置权限...${reset}"
chown -R www-data:www-data "$RCDIR"
chmod -R 755 "$RCDIR"

# 给自己加执行权限
chmod +x /root/VPN/menu/mail/install_mail.sh

echo -e "${green}✅ Roundcube 安装文件准备完成，依赖已安装，源码已就位。${reset}"
echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

read -p "按回车返回..." 
bash /root/VPN/menu/mail.sh
