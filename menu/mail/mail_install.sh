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

# 单个包安装函数，返回成功失败
install_single() {
  local pkg=$1
  echo -n "🔍 安装 ${pkg}..."
  if apt install -y $pkg > /dev/null 2>&1; then
    echo -e "${green} ✓ 安装成功${reset}"
    return 0
  else
    echo -e "${red} ✗ 安装失败${reset}"
    return 1
  fi
}

# 分类批量安装函数
install_category() {
  local title="$1"
  shift
  local packages=("$@")
  local success_count=0
  local fail_count=0

  draw_header
  echo -e "${yellow}${title}${reset}"

  for pkg in "${packages[@]}"; do
    install_single "$pkg"
    if [ $? -eq 0 ]; then
      success_count=$((success_count+1))
    else
      fail_count=$((fail_count+1))
    fi
  done

  if [ $fail_count -eq 0 ]; then
    echo -e "${green}✅ ${title}全部安装成功${reset}"
  else
    echo -e "${red}⚠ ${title}安装部分失败（成功${success_count}个，失败${fail_count}个）${reset}"
  fi
  draw_footer
  sleep 1
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

# 分类安装
install_category "📦 安装邮件服务组件..." postfix dovecot-core dovecot-imapd dovecot-mysql
install_category "🛢️ 安装数据库服务..." mariadb-server
install_category "🌐 安装Web服务器..." apache2
install_category "🧩 安装PHP及扩展..." php php-cli php-fpm php-mysql php-imap php-json php-intl php-gd

# Roundcube安装（下载到 /root/VPN/MAIL）
draw_header
echo -e "${yellow}📬 下载并准备 Roundcube...${reset}"
cd /root/VPN/MAIL
if wget -qO roundcube.tar.gz https://github.com/roundcube/roundcubemail/releases/download/1.6.6/roundcubemail-1.6.6-complete.tar.gz; then
  tar -xzf roundcube.tar.gz
  rm -rf roundcube.tar.gz
  mv roundcubemail-1.6.6 roundcube
  echo -e "${green}✅ Roundcube下载解压完成${reset}"
else
  echo -e "${red}❌ Roundcube下载失败${reset}"
fi
draw_footer
sleep 1

# 安装OpenDKIM和Certbot
install_category "🔒 安装邮件认证和HTTPS工具..." opendkim opendkim-tools certbot

# 安装完成
draw_header
echo -e "${green}✅ 邮局系统所有组件安装完成！${reset}"
draw_footer

# 返回主菜单提示
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
