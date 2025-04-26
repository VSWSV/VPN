#!/bin/bash
clear

# 颜色定义
cyan='\033[0;36m'
orange='\033[38;5;208m'
green='\033[0;32m'
red='\033[0;31m'
reset='\033[0m'

# 边框函数
top_border() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
}
middle_border() {
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}
bottom_border() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

top_border
echo -e "✦ ${orange}邮局系统卸载程序${reset}"
middle_border

# 需要卸载的软件列表
packages=(
  postfix dovecot-core dovecot-imapd dovecot-mysql
  mariadb-server mariadb-client
  apache2 php php-cli php-fpm
  php-mysql php-imap php-json php-intl php-gd
  opendkim opendkim-tools certbot
)

echo -e "${green}▶ 正在卸载相关软件包...${reset}"
apt purge -y "${packages[@]}" > /dev/null 2>&1
apt autoremove -y > /dev/null 2>&1

echo -e "${green}▶ 软件包卸载完成${reset}"

middle_border

# 删除Roundcube目录
if [ -d /var/www/html/roundcube ]; then
  echo -e "${green}▶ 正在删除 Roundcube 文件...${reset}"
  rm -rf /var/www/html/roundcube
  echo -e "${green}✓ Roundcube目录已删除${reset}"
else
  echo -e "${yellow}⚠ Roundcube目录不存在，跳过${reset}"
fi

# 删除Apache虚拟主机配置
if [ -f /etc/apache2/sites-available/roundcube.conf ]; then
  echo -e "${green}▶ 正在删除 Roundcube Apache 配置...${reset}"
  a2dissite roundcube.conf > /dev/null 2>&1
  rm -f /etc/apache2/sites-available/roundcube.conf
  systemctl reload apache2
  echo -e "${green}✓ Apache配置已删除${reset}"
else
  echo -e "${yellow}⚠ Apache Roundcube配置不存在，跳过${reset}"
fi

bottom_border

top_border
echo -e "✦ ${orange}卸载完成${reset}"
middle_border
echo -e "${green}🎯 邮局系统相关内容已全部清理！${reset}"
bottom_border

read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
