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

# 单个包安装函数
install_single() {
  local pkg=$1
  echo -n "🔍 安装 ${pkg}..."
  if apt install -y $pkg > /dev/null 2>&1; then
    echo -e "${green} ✓ 安装成功${reset}"
  else
    echo -e "${red} ✗ 安装失败${reset}"
  fi
}

# 创建目录
draw_header
echo -e "${green}▶ 正在创建 /root/VPN/MAIL 目录...${reset}"
mkdir -p /root/VPN/MAIL
chmod 755 /root/VPN/MAIL
sleep 1
draw_footer
sleep 1

# 更新源
draw_header
echo -e "${green}▶ 更新系统源中...${reset}"
apt update -y > /dev/null 2>&1 && echo -e "${green}✅ 系统更新完成${reset}" || echo -e "${red}❌ 系统更新失败${reset}"
draw_footer
sleep 1

# 分类安装开始
# 邮件服务
draw_header
echo -e "${yellow}📦 安装邮件服务组件...${reset}"
install_single postfix
install_single dovecot-core
install_single dovecot-imapd
install_single dovecot-mysql
echo -e "${green}✅ 邮件服务安装完成${reset}"
draw_footer
sleep 1

# 数据库
draw_header
echo -e "${yellow}🛢️ 安装数据库服务...${reset}"
install_single mariadb-server
echo -e "${green}✅ 数据库安装完成${reset}"
draw_footer
sleep 1

# Web服务器
draw_header
echo -e "${yellow}🌐 安装Web服务器...${reset}"
install_single apache2
echo -e "${green}✅ Web服务器安装完成${reset}"
draw_footer
sleep 1

# PHP及扩展
draw_header
echo -e "${yellow}🧩 安装PHP及扩展...${reset}"
install_single php
install_single php-cli
install_single php-fpm
install_single php-mysql
install_single php-imap
install_single php-json
install_single php-intl
install_single php-gd
echo -e "${green}✅ PHP及扩展安装完成${reset}"
draw_footer
sleep 1

# Roundcube安装（下载到 /root/VPN/MAIL）
draw_header
echo -e "${yellow}📬 下载并准备 Roundcube...${reset}"
cd /root/VPN/MAIL
if wget -O roundcube.tar.gz https://github.com/roundcube/roundcubemail/releases/download/1.6.6/roundcubemail-1.6.6-complete.tar.gz > /dev/null 2>&1; then
  tar -xzf roundcube.tar.gz
  mv roundcubemail-1.6.6 roundcube
  rm -f roundcube.tar.gz
  echo -e "${green}✅ Roundcube下载解压完成${reset}"
else
  echo -e "${red}❌ Roundcube下载失败${reset}"
fi
draw_footer
sleep 1

# 安装OpenDKIM和Certbot
draw_header
echo -e "${yellow}🔒 安装邮件认证和HTTPS工具...${reset}"
install_single opendkim
install_single opendkim-tools
install_single certbot
echo -e "${green}✅ OpenDKIM和Certbot安装完成${reset}"
draw_footer
sleep 1

# 安装完成
draw_header
echo -e "${green}✅ 邮局系统所有组件安装完成！${reset}"
draw_footer

# 返回主菜单提示
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
