#!/bin/bash

clear

# 颜色定义
cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
reset="\033[0m"

# 卸载统计
success_uninstall=0
fail_uninstall=0

# 边框输出
function draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                               ${orange}📦 邮局系统卸载${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}
function draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 停止并卸载服务
function stop_and_remove_service() {
  local service_name=$1
  echo -n "🔍 处理 ${service_name}..."
  systemctl stop $service_name > /dev/null 2>&1
  apt purge -y $service_name > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${green} ✓ 已卸载${reset}"
    success_uninstall=$((success_uninstall+1))
  else
    echo -e "${red} ✗ 卸载失败${reset}"
    fail_uninstall=$((fail_uninstall+1))
  fi
}

# 删除目录
function remove_directory() {
  local dir_path=$1
  echo -n "🔍 删除 ${dir_path}..."
  rm -rf $dir_path
  if [ ! -d "$dir_path" ]; then
    echo -e "${green} ✓ 已删除${reset}"
    success_uninstall=$((success_uninstall+1))
  else
    echo -e "${red} ✗ 删除失败${reset}"
    fail_uninstall=$((fail_uninstall+1))
  fi
}

# 开始卸载
draw_header

# 停止并卸载主要服务
stop_and_remove_service postfix
stop_and_remove_service dovecot-core
stop_and_remove_service dovecot-imapd
stop_and_remove_service dovecot-mysql
stop_and_remove_service mariadb-server
stop_and_remove_service apache2
stop_and_remove_service php
stop_and_remove_service php-cli
stop_and_remove_service php-fpm
stop_and_remove_service php-mysql
stop_and_remove_service php-imap
stop_and_remove_service php-json
stop_and_remove_service php-intl
stop_and_remove_service php-gd
stop_and_remove_service opendkim
stop_and_remove_service opendkim-tools
stop_and_remove_service certbot

# 删除应用文件目录
remove_directory /root/VPN/MAIL
remove_directory /var/www/html/roundcube

# 删除配置文件目录
remove_directory /etc/postfix
remove_directory /etc/dovecot
remove_directory /etc/apache2
remove_directory /etc/roundcube

# 清理残余
echo -n "🔍 清理残余缓存..."
apt autoremove -y > /dev/null 2>&1 && apt clean > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo -e "${green} ✓ 完成${reset}"
else
  echo -e "${red} ✗ 失败${reset}"
fi

# 收尾
draw_footer

# 总结结果
if [ $fail_uninstall -eq 0 ]; then
  echo -e "${green}✅ 邮局系统所有组件卸载完成！${reset}"
else
  echo -e "${red}⚠ 邮局系统卸载部分失败，请检查上方日志${reset}"
fi

# 返回主菜单提示
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
