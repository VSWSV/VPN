#!/bin/bash

clear

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
  echo -e "                               ${orange}📦 邮局系统卸载${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

function uninstall_package() {
  local pkg=$1
  echo -n "🔍 处理 ${pkg}..."
  if dpkg -s "$pkg"; then
    apt purge -y "$pkg"
    if [ $? -eq 0 ]; then
      echo -e "${green} ✓ 已卸载${reset}"
      success_all=$((success_all+1))
    else
      echo -e "${red} ✗ 卸载失败${reset}"
      fail_all=$((fail_all+1))
    fi
  else
    echo -e "${yellow} ⚠ 已不存在，跳过${reset}"
  fi
}

function remove_directory() {
  local dir=$1
  echo -n "🔍 删除 ${dir}..."
  if [ -d "$dir" ]; then
    rm -rf "$dir"
    if [ ! -d "$dir" ]; then
      echo -e "${green} ✓ 已删除${reset}"
      success_all=$((success_all+1))
    else
      echo -e "${red} ✗ 删除失败${reset}"
      fail_all=$((fail_all+1))
    fi
  else
    echo -e "${yellow} ⚠ 不存在，跳过${reset}"
  fi
}

# 密码确认
echo -e "${yellow}⚡ 卸载操作需要输入密码确认${reset}"
read -p "请输入密码以继续（默认密码: 88）: " user_pass

if [ "$user_pass" != "88" ]; then
  echo -e "${red}❌ 密码错误，卸载已取消！${reset}"
  sleep 0.5
  bash /root/VPN/menu/mail.sh
  exit 1
else
  echo -e "${green}✅ 密码正确，开始卸载！${reset}"
  sleep 0.5
fi

# 开始卸载
draw_header

# 卸载安装的包
uninstall_package postfix
uninstall_package dovecot-core
uninstall_package dovecot-imapd
uninstall_package dovecot-mysql
uninstall_package mariadb-server
uninstall_package apache2
uninstall_package php
uninstall_package php-cli
uninstall_package php-fpm
uninstall_package php-mysql
uninstall_package php-imap
uninstall_package php-json
uninstall_package php-intl
uninstall_package php-gd
uninstall_package opendkim
uninstall_package opendkim-tools
uninstall_package certbot

# 删除目录
remove_directory /root/VPN/MAIL
remove_directory /var/www/html/roundcube

# 清理缓存
echo -n "🔍 清理系统残余..."
apt autoremove -y && apt clean
if [ $? -eq 0 ]; then
  echo -e "${green} ✓ 完成${reset}"
else
  echo -e "${red} ✗ 清理失败${reset}"
fi

# 收尾输出
draw_footer

if [ $fail_all -eq 0 ]; then
  echo -e "${green}✅ 邮局系统所有组件卸载完成！${reset}"
else
  echo -e "${red}⚠ 邮局系统卸载部分失败，请检查上方日志${reset}"
fi

read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
