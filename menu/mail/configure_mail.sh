#!/bin/bash

INSTALL_DIR="/root/VPN/MAIL"
CONFIG_FILE="/etc/postfix/main.cf"
DOVECOT_CONFIG="/etc/dovecot/dovecot.conf"
ROUNDCUBE_CONFIG="/var/www/roundcube/config/config.inc.php"

# 颜色定义
blue="\033[1;34m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
cyan="\033[1;36m"
magenta="\033[1;35m"
reset="\033[0m"

cecho() {
  local color=$1
  shift
  echo -e "${color}$*${reset}"
}

configure_domain() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 📧 邮局域名配置${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请输入您的邮件域名 (例如: example.com): ${reset}")" domain
  echo -e "${blue}📝 输入为: ${green}$domain${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请输入服务器主机名 (例如: mail.example.com): ${reset}")" hostname
  echo -e "${blue}📝 输入为: ${green}$hostname${reset}"
  
  # 配置Postfix
  sed -i "s/myhostname = .*/myhostname = $hostname/" $CONFIG_FILE
  sed -i "s/mydomain = .*/mydomain = $domain/" $CONFIG_FILE
  
  # 配置Dovecot
  echo "ssl_cert = </etc/letsencrypt/live/$hostname/fullchain.pem" >> $DOVECOT_CONFIG
  echo "ssl_key = </etc/letsencrypt/live/$hostname/privkey.pem" >> $DOVECOT_CONFIG
  
  # 配置Roundcube
  if [ -f $ROUNDCUBE_CONFIG ]; then
    sed -i "s/\$config\['default_host'\] = .*/\$config\['default_host'\] = 'ssl:\/\/$hostname';/" $ROUNDCUBE_CONFIG
    sed -i "s/\$config\['smtp_server'\] = .*/\$config\['smtp_server'\] = 'tls:\/\/$hostname';/" $ROUNDCUBE_CONFIG
  fi
  
  echo -e "${green}✅ 域名配置完成!${reset}"
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
  
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  bash /root/VPN/menu/mail.sh
}

configure_database() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 🗃️ 数据库配置${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请输入MySQL root密码: ${reset}")" -s rootpass
  echo -e "\n${blue}📝 输入为: ${green}[密码已隐藏]${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请输入新数据库名称: ${reset}")" dbname
  echo -e "${blue}📝 输入为: ${green}$dbname${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请输入新数据库用户名: ${reset}")" dbuser
  echo -e "${blue}📝 输入为: ${green}$dbuser${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请输入新数据库密码: ${reset}")" -s dbpass
  echo -e "\n${blue}📝 输入为: ${green}[密码已隐藏]${reset}"
  
  mysql -uroot -p"$rootpass" <<EOF
CREATE DATABASE $dbname;
CREATE USER '$dbuser'@'localhost' IDENTIFIED BY '$dbpass';
GRANT ALL PRIVILEGES ON $dbname.* TO '$dbuser'@'localhost';
FLUSH PRIVILEGES;
EOF
  
  # 导入Roundcube数据库结构
  mysql -uroot -p"$rootpass" $dbname < /var/www/roundcube/SQL/mysql.initial.sql
  
  # 更新Roundcube配置
  sed -i "s/\$config\['db_dsnw'\] = .*/\$config\['db_dsnw'\] = 'mysql:\/\/$dbuser:$dbpass@localhost\/$dbname';/" $ROUNDCUBE_CONFIG
  
  echo -e "${green}✅ 数据库配置完成!${reset}"
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
  
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  bash /root/VPN/menu/mail.sh
}

main_menu() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 ⚙️ 邮局配置菜单${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  echo -e "${green}① 配置邮件域名${reset}"
  echo -e "${green}② 配置数据库${reset}"
  echo -e "${green}③ 返回主菜单${reset}"
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请选择操作 [1-3]: ${reset}")" choice
  case $choice in
    1) configure_domain ;;
    2) configure_database ;;
    3) bash /root/VPN/menu/mail.sh ;;
    *) echo -e "${red}✗ 无效选择!${reset}"; sleep 1; main_menu ;;
  esac
}

main_menu
