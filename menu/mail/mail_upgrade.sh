#!/bin/bash

clear

# 颜色定义
cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
reset="\033[0m"

# 边框和标题输出
function draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                               ${orange}📬 邮局系统安装${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 创建目录
echo -e "${green}▶ 正在创建 /root/VPN/MAIL 目录...${reset}"
mkdir -p /root/VPN/MAIL
chmod 755 /root/VPN/MAIL
sleep 1

# 更新源
draw_header
echo -e "${green}▶ 更新系统源中...${reset}"
apt update -y
sleep 2

# 分类安装开始
draw_header
echo -e "${yellow}📦 安装邮件服务组件...${reset}"
apt install -y postfix dovecot-core dovecot-imapd dovecot-mysql && echo -e "${green}✅ 邮件服务安装完成${reset}" || echo -e "${red}❌ 邮件服务安装失败${reset}"
sleep 2

draw_header
echo -e "${yellow}🛢️ 安装数据库服务...${reset}"
apt install -y mariadb-server && echo -e "${green}✅ 数据库安装完成${reset}" || echo -e "${red}❌ 数据库安装失败${reset}"
sleep 2

draw_header
echo -e "${yellow}🌐 安装Web服务器...${reset}"
apt install -y apache2 && echo -e "${green}✅ Web服务器安装完成${reset}" || echo -e "${red}❌ Web服务器安装失败${reset}"
sleep 2

draw_header
echo -e "${yellow}🧩 安装PHP及扩展...${reset}"
apt install -y php php-cli php-fpm php-mysql php-imap php-json php-intl php-gd && echo -e "${green}✅ PHP及扩展安装完成${reset}" || echo -e "${red}❌ PHP及扩展安装失败${reset}"
sleep 2

# Roundcube安装（下载到 /root/VPN/MAIL）
draw_header
echo -e "${yellow}📬 下载并准备 Roundcube...${reset}"
cd /root/VPN/MAIL
wget -O roundcube.tar.gz https://github.com/roundcube/roundcubemail/releases/download/1.6.6/roundcubemail-1.6.6-complete.tar.gz && \
  tar -xzf roundcube.tar.gz && \
  mv roundcubemail-1.6.6 roundcube && \
  rm -f roundcube.tar.gz && \
  echo -e "${green}✅ Roundcube下载解压完成${reset}" || echo -e "${red}❌ Roundcube下载失败${reset}"
sleep 2

draw_header
echo -e "${yellow}🔒 安装邮件认证和HTTPS工具...${reset}"
apt install -y opendkim opendkim-tools certbot && echo -e "${green}✅ OpenDKIM和Certbot安装完成${reset}" || echo -e "${red}❌ OpenDKIM/Certbot安装失败${reset}"
sleep 2

# 安装完成

clear
draw_header
echo -e "${green}✅ 邮局系统所有组件安装完成！${reset}"
draw_footer

# 返回主菜单提示
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
