#!/bin/bash

# ==============================================
# 邮件系统配置脚本
# 完整功能版 | 保留所有原始设计元素
# ==============================================

INSTALL_DIR="/root/VPN/MAIL"
CONFIG_FILE="/etc/postfix/main.cf"
DOVECOT_CONFIG="/etc/dovecot/dovecot.conf"

# 颜色和边框函数（同上）

setup_domain() {
  draw_top
  echo -e "${orange}                 📧 邮局域名配置                ${reset}"
  draw_mid
  
  read -p "$(echo -e "${yellow}✨ 请输入您的邮件域名 (例如: example.com): ${reset}")" domain
  echo -e "${blue}📝 输入为: ${green}$domain${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请输入服务器主机名 (例如: mail.example.com): ${reset}")" hostname
  echo -e "${blue}📝 输入为: ${green}$hostname${reset}"
  
  # 配置Postfix
  echo -e "${orange}① 配置Postfix...${reset}"
  postconf -e "myhostname = $hostname"
  postconf -e "mydomain = $domain"
  
  # 配置Dovecot
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
  DB_PASS=$(openssl rand -hex 10)
  
  echo -e "${orange}① 创建数据库...${reset}"
  mysql -uroot -p"$rootpass" <<MYSQL_SCRIPT
CREATE DATABASE $DB_NAME;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

  echo -e "${orange}② 创建表结构...${reset}"
  mysql -uroot -p"$rootpass" $DB_NAME <<EOF
CREATE TABLE virtual_domains (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(50) NOT NULL UNIQUE);
CREATE TABLE virtual_users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  domain_id INT NOT NULL,
  email VARCHAR(100) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
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

# 主菜单
main_menu() {
  while true; do
    draw_top
    echo -e "${orange}                 ⚙️ 邮局配置菜单                ${reset}"
    draw_mid
    
    echo -e "${green}① 配置邮件域名${reset}"
    echo -e "${green}② 配置数据库${reset}"
    echo -e "${green}③ 返回主菜单${reset}"
    draw_mid
    
    read -p "$(echo -e "${yellow}✨ 请选择操作: ${reset}")" choice
    
    case $choice in
      1) setup_domain ;;
      2) setup_database ;;
      3) break ;;
      *) echo -e "${red}✗ 无效选择!${reset}"; sleep 1 ;;
    esac
  done
}

main_menu
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
