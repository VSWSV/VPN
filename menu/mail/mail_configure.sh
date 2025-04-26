#!/bin/bash

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
  4) exit ;;
  *) echo -e "${red}✗ 无效选择!${reset}"; sleep 1 ;;
esac

# DNS 配置指南函数
show_dns_guide() {
  draw_top
  echo -e "${orange}                  🌐 DNS配置指南                 ${reset}"
  draw_mid
  read -p "$(echo -e "${yellow}✨ 请输入您的邮件域名 (例如: example.com): ${reset}")" domain
  echo -e "${blue}📝 输入为: ${green}$domain${reset}"
  echo -e "${yellow}请为域名 ${green}$domain${yellow} 添加以下 DNS 记录：${reset}"
  echo -e "${green}① A记录：@ → 服务器公网 IP${reset}"
  echo -e "${green}② A记录：mail → 服务器公网 IP${reset}"
  echo -e "${green}③ MX记录：@ → mail.$domain （优先级 10）${reset}"
  echo -e "${green}④ TXT记录：@ → v=spf1 mx ~all${reset}"
  echo -e "${green}⑤ TXT记录：_dmarc → v=DMARC1; p=none; rua=mailto:postmaster@$domain${reset}"
  draw_mid
  echo -e "${yellow}🔔 重要提示：${reset}"
  echo -e "${blue}• DKIM 公钥记录需要使用 opendkim 生成后手动添加${reset}"
  echo -e "${blue}• PTR 记录需联系提供商设置${reset}"
  draw_bottom
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

# 域名配置函数
setup_domain() {
  draw_top
  echo -e "${orange}                 📧 邮局域名配置                ${reset}"
  draw_mid
  read -p "$(echo -e "${yellow}✨ 请输入您的邮件域名 (例如: example.com): ${reset}")" domain
  echo -e "${blue}📝 输入为: ${green}$domain${reset}"
  read -p "$(echo -e "${yellow}✨ 请输入服务器主机名 (例如: mail.example.com): ${reset}")" hostname
  echo -e "${blue}📝 输入为: ${green}$hostname${reset}"
  echo -e "${orange}① 配置 Postfix...${reset}"
  postconf -e "myhostname = $hostname"
  postconf -e "mydomain = $domain"
  postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
  echo -e "${orange}② 配置 Dovecot...${reset}"
  DOVECOT_CONF="/etc/dovecot/conf.d/10-ssl.conf"
  echo "ssl_cert = </etc/letsencrypt/live/$hostname/fullchain.pem" >> $DOVECOT_CONF
  echo "ssl_key = </etc/letsencrypt/live/$hostname/privkey.pem" >> $DOVECOT_CONF
  draw_mid
  echo -e "${green}✅ 域名配置完成!${reset}"
  echo -e "${blue}🌍 Roundcube 访问: ${green}https://$hostname/roundcube${reset}"
  draw_bottom
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

# 数据库配置函数
setup_database() {
  draw_top
  echo -e "${orange}                 🗃️ 数据库配置                  ${reset}"
  draw_mid
  read -p "$(echo -e "${yellow}✨ 请输入 MySQL root 密码: ${reset}")" -s rootpass
  echo -e "\n${blue}📝 输入为: ${green}[密码已隐藏]${reset}"
  DB_NAME="maildb_$(date +%Y%m%d)"
  DB_USER="mail_admin"
  DB_PASS=$(openssl rand -hex 12)
  echo -e "${orange}① 创建数据库...${reset}"
  mysql -uroot -p"$rootpass" <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
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
  echo -e "${blue}🔑 数据库信息:${reset}"
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
