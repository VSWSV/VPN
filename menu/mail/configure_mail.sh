#!/bin/bash

INSTALL_DIR="/root/VPN/MAIL"
CONFIG_FILE="/etc/postfix/main.cf"
DOVECOT_CONFIG="/etc/dovecot/dovecot.conf"

blue="\033[1;34m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
cyan="\033[1;36m"
reset="\033[0m"

draw_top() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
}
draw_mid() {
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}
draw_bottom() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

show_dns_guide() {
  draw_top
  echo -e "${orange}                  🌐 DNS配置指南                 ${reset}"
  draw_mid
  
  read -p "$(echo -e "${yellow}✨ 请输入您的邮件域名 (例如: example.com): ${reset}")" domain
  echo -e "${blue}📝 输入为: ${green}$domain${reset}"
  
  server_ip=$(hostname -I | awk '{print $1}')
  
  echo -e "${yellow}请为域名 ${green}$domain${yellow} 添加以下DNS记录：${reset}"
  echo -e "${green}① A记录：@ → $server_ip${reset}"
  echo -e "${green}② A记录：mail → $server_ip${reset}"
  echo -e "${green}③ MX记录：@ → mail.$domain (优先级10)${reset}"
  echo -e "${green}④ TXT记录：@ → v=spf1 mx ~all${reset}"
  echo -e "${green}⑤ TXT记录：_dmarc → v=DMARC1; p=none; rua=mailto:postmaster@$domain${reset}"
  
  draw_mid
  echo -e "${yellow}🔔 重要提示：${reset}"
  echo -e "${blue}• PTR记录需要联系服务器提供商设置${reset}"
  echo -e "${blue}• 测试命令: ${green}dig MX $domain${blue} 或 ${green}nslookup mail.$domain${reset}"
  draw_bottom
  
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

setup_domain() {
  draw_top
  echo -e "${orange}                 📧 邮局域名配置                ${reset}"
  draw_mid
  
  read -p "$(echo -e "${yellow}✨ 请输入您的邮件域名 (例如: example.com): ${reset}")" domain
  echo -e "${blue}📝 输入为: ${green}$domain${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请输入服务器主机名 (例如: mail.example.com): ${reset}")" hostname
  echo -e "${blue}📝 输入为: ${green}$hostname${reset}"
  
  echo -e "${orange}① 配置Postfix...${reset}"
  postconf -e "myhostname = $hostname"
  postconf -e "mydomain = $domain"
  postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
  
  echo -e "${orange}② 配置Dovecot...${reset}"
  echo "ssl_cert = </etc/letsencrypt/live/$hostname/fullchain.pem" >> $DOVECOT_CONFIG
  echo "ssl_key = </etc/letsencrypt/live/$hostname/privkey.pem" >> $DOVECOT_CONFIG
  
  draw_mid
  echo -e "${green}✅ 域名配置完成!${reset}"
  echo -e "${blue}🌍 访问地址: ${green}https://$hostname/roundcube${reset}"
  draw_bottom
  
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

setup_database() {
  draw_top
  echo -e "${orange}                 🗃️ 数据库配置                  ${reset}"
  draw_mid
  
  read -p "$(echo -e "${yellow}✨ 请输入MySQL root密码: ${reset}")" -s rootpass
  echo -e "\n${blue}📝 输入为: ${green}[密码已隐藏]${reset}"
  
  DB_NAME="maildb_$(date +%Y%m%d)"
  DB_USER="mail_admin"
  DB_PASS=$(openssl rand -hex 12)
  
  echo -e "${orange}① 创建数据库...${reset}"
  mysql -uroot -p"$rootpass" <<MYSQL_SCRIPT
CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

  echo -e "${orange}② 创建表结构...${reset}"
  mysql -uroot -p"$rootpass" $DB_NAME <<EOF
CREATE TABLE virtual_domains (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50) NOT NULL UNIQUE
);
CREATE TABLE virtual_users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  domain_id INT NOT NULL,
  email VARCHAR(100) NOT NULL UNIQUE,
  password VARCHAR(106) NOT NULL,
  FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
);
CREATE TABLE virtual_aliases (
  id INT AUTO_INCREMENT PRIMARY KEY,
  domain_id INT NOT NULL,
  source VARCHAR(100) NOT NULL,
  destination VARCHAR(100) NOT NULL,
  FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
);
EOF

  draw_mid
  echo -e "${green}✅ 数据库配置完成!${reset}"
  echo -e "${blue}🔑 数据库信息:"
  echo -e "名称: ${green}$DB_NAME${reset}"
  echo -e "用户: ${green}$DB_USER${reset}"
  echo -e "密码: ${green}$DB_PASS${reset}"
  draw_bottom
  
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

main_menu() {
  while true; do
    draw_top
    echo -e "${orange}                 ⚙️ 邮局配置菜单                ${reset}"
    draw_mid
    
    echo -e "${green}① DNS配置指南${reset}"
    echo -e "${green}② 配置邮件域名${reset}"
    echo -e "${green}③ 配置数据库${reset}"
    echo -e "${green}④ 返回主菜单${reset}"
    draw_mid
    
    read -p "$(echo -e "${yellow}✨ 请选择操作: ${reset}")" choice
    
    case $choice in
      1) show_dns_guide ;;
      2) setup_domain ;;
      3) setup_database ;;
      4) break ;;
      *) echo -e "${red}✗ 无效选择!${reset}"; sleep 1 ;;
    esac
  done
}

main_menu
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
