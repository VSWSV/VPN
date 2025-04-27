#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
clear

# ==============================
# 📬 邮局系统 安装脚本
# ==============================

# 颜色定义
cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
reset="\033[0m"

success_all=0
fail_all=0

function draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                               ${orange}📬 邮局系统安装${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 密码确认
echo -e "${yellow}⚡ 安装操作需要输入密码确认${reset}"
read -p "请输入密码以继续（默认密码: 88）: " user_pass

if [ "$user_pass" != "88" ]; then
  echo -e "${red}❌ 密码错误，安装已取消，返回菜单！${reset}"
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  sleep 0.5
  bash /root/VPN/menu/mail.sh
else
  echo -e "${green}✅ 密码正确，开始安装！${reset}"
  sleep 0.5
  draw_header
fi

# 单包安装函数
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

# 分类安装
install_category() {
  local title="$1"
  shift
  local packages=("$@")
  local success_count=0
  local fail_count=0

  echo -e "${yellow}${title}${reset}"

  for pkg in "${packages[@]}"; do
    install_single "$pkg"
    if [ $? -eq 0 ]; then
      success_count=$((success_count+1))
    else
      fail_count=$((fail_count+1))
    fi
  done

  success_all=$((success_all+success_count))
  fail_all=$((fail_all+fail_count))

  if [ $fail_count -eq 0 ]; then
    echo -e "${green}✅ ${title}全部安装成功${reset}\n"
  else
    echo -e "${red}⚠ ${title}安装部分失败（成功${success_count}个，失败${fail_count}个）${reset}\n"
  fi
}

# 清理旧目录并切换到安全目录
cd /root
if [ -d "/root/VPN/MAIL" ]; then
  echo -e "${yellow}⚡ 检测到已有 /root/VPN/MAIL，正在强制清理...${reset}"
  rm -rf /root/VPN/MAIL
fi

echo -e "${green}▶ 正在创建 /root/VPN/MAIL 目录...${reset}"
mkdir -p /root/VPN/MAIL
chmod 755 /root/VPN/MAIL
sleep 1

# 更新源
echo -e "${green}▶ 更新系统源中...${reset}"
apt update -y > /dev/null 2>&1 && echo -e "${green}✅ 系统更新完成${reset}" || echo -e "${red}❌ 系统更新失败${reset}"
sleep 1

# 分类安装
install_category "📦 安装邮件服务组件..." postfix dovecot-core dovecot-imapd dovecot-mysql
install_category "🛢️ 安装数据库服务..." mariadb-server
install_category "🌐 安装Web服务器..." apache2
install_category "🧩 安装PHP及扩展..." php php-cli php-fpm php-mysql php-imap php-json php-intl php-gd
install_category "🔒 安装邮件认证和HTTPS工具..." opendkim opendkim-tools certbot

# Roundcube安装
success_roundcube=0
fail_roundcube=0

echo -e "${yellow}📬 安装Roundcube...${reset}"
cd /root/VPN/MAIL

echo -n "🔍 下载 Roundcube源码..."
if wget -qO roundcube.tar.gz https://github.com/roundcube/roundcubemail/releases/download/1.6.6/roundcubemail-1.6.6-complete.tar.gz; then
  echo -e "${green} ✓ 成功${reset}"
  success_roundcube=$((success_roundcube+1))
else
  echo -e "${red} ✗ 失败${reset}"
  fail_roundcube=$((fail_roundcube+1))
fi

echo -n "🔍 解压 Roundcube源码..."
if tar -xzf roundcube.tar.gz > /dev/null 2>&1; then
  rm -f roundcube.tar.gz
  echo -e "${green} ✓ 成功${reset}"
  success_roundcube=$((success_roundcube+1))
else
  echo -e "${red} ✗ 失败${reset}"
  fail_roundcube=$((fail_roundcube+1))
fi

echo -n "🔍 安装 Roundcube..."
if [ -d "roundcubemail-1.6.6" ]; then
  mkdir -p roundcube
  mv roundcubemail-1.6.6/* roundcube/ 2>/dev/null && echo -e "${green} ✓ 成功${reset}" || {
    echo -e "${red} ✗ 失败${reset}"; fail_roundcube=$((fail_roundcube+1));
  }
else
  echo -e "${red} ✗ 失败${reset}"
  fail_roundcube=$((fail_roundcube+1))
fi

echo -n "▶ 修复 Roundcube目录权限..."
if [ -d "/root/VPN/MAIL/roundcube" ]; then
  chown -R www-data:www-data /root/VPN/MAIL/roundcube > /dev/null 2>&1 && echo -e "${green} ✓ 成功${reset}" || {
    echo -e "${red} ✗ 失败${reset}"; fail_roundcube=$((fail_roundcube+1));
  }
else
  echo -e "${red} ✗ 失败${reset}"
  fail_roundcube=$((fail_roundcube+1))
fi

success_all=$((success_all+success_roundcube))
fail_all=$((fail_all+fail_roundcube))

if [ $fail_roundcube -eq 0 ]; then
  echo -e "${green}✅ 📬 安装Roundcube全部完成${reset}\n"
else
  echo -e "${red}⚠ 📬 安装Roundcube部分失败（成功${success_roundcube}个，失败${fail_roundcube}个）${reset}\n"
fi

sleep 1
draw_footer

if [ $fail_all -eq 0 ]; then
  echo -e "${green}✅ 邮局系统所有组件安装成功！${reset}"
else
  echo -e "${red}⚠ 邮局系统安装部分失败，请检查上方安装日志${reset}"
fi

read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
