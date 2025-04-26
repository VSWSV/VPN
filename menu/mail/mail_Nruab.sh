#!/bin/bash

INSTALL_DIR="/root/VPN/MAIL"
LOG_FILE="$INSTALL_DIR/install.log"
mkdir -p "$INSTALL_DIR" && chmod 700 "$INSTALL_DIR"
> "$LOG_FILE"

# 颜色定义
blue="\033[1;34m"; green="\033[1;32m"; yellow="\033[1;33m"; red="\033[1;31m"
orange="\033[38;5;214m"; cyan="\033[1;36m"; reset="\033[0m"

# 边框函数
draw_top() { echo -e "${cyan}╔════════════════════════════════════════════════════════════════════════════╗${reset}"; }
draw_mid() { echo -e "${cyan}╠════════════════════════════════════════════════════════════════════════════╣${reset}"; }
draw_bottom() { echo -e "${cyan}╚════════════════════════════════════════════════════════════════════════════╝${reset}"; }

# 安全安装函数：若未安装则执行 apt-get，否则跳过
safe_install() {
  local pkg="$1" step="$2" desc="$3"
  echo -e "${orange}${step} ${desc}...${reset}"
  if dpkg -l | grep -q "^ii  $pkg "; then
    echo -e "${yellow}⚠ 已安装: ${green}$pkg${reset}"
    return 0
  fi
  apt-get install -y "$pkg" >> "$LOG_FILE" 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${green}✓ 安装成功: ${pkg}${reset}"
  else
    echo -e "${red}✗ 安装失败: ${pkg}${reset}"
    exit 1
  fi
}

# 部署 Roundcube（稳定版 1.6.3）
install_roundcube() {
  echo -e "${orange}⑦ 部署 Roundcube...${reset}"
  [ -d "/var/www/roundcube" ] && rm -rf /var/www/roundcube
  wget -q https://github.com/roundcube/roundcubemail/releases/download/1.6.3/roundcubemail-1.6.3-complete.tar.gz -O /tmp/roundcube.tar.gz
  tar -xzf /tmp/roundcube.tar.gz -C /var/www
  mv /var/www/roundcubemail-1.6.3 /var/www/roundcube
  rm -f /tmp/roundcube.tar.gz
  chown -R www-data:www-data /var/www/roundcube
  echo -e "${green}✓ Roundcube 部署成功 (v1.6.3)${reset}"
}

# 初始化 Roundcube 数据库
init_roundcube_db() {
  echo -e "${orange}⑧ 初始化 Roundcube 数据库...${reset}"
  mysql -uroot <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS roundcubedb DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS 'roundcube'@'localhost' IDENTIFIED BY 'roundcube_password';
GRANT ALL PRIVILEGES ON roundcubedb.* TO 'roundcube'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
  mysql -uroot roundcubedb < /var/www/roundcube/SQL/mysql.initial.sql 2>&1 | grep -v "already exists"
  [ ${PIPESTATUS[0]} -eq 0 ] && echo -e "${green}✓ Roundcube 数据库初始化完成${reset}" || echo -e "${red}✗ Roundcube 数据库初始化失败${reset}"
}

# 主流程
draw_top
echo -e "${orange}                    📮 邮局系统安装                 ${reset}"
draw_mid

# 1. 更新软件包列表
echo -e "${orange}① 更新软件包列表...${reset}"
apt-get update >> "$LOG_FILE" 2>&1
[ $? -eq 0 ] && echo -e "${green}✓ 更新完成${reset}" || { echo -e "${red}✗ 更新失败${reset}"; exit 1; }

# 2. 安装系统工具
safe_install "tree" "②" "安装系统工具"
safe_install "curl" "" ""
safe_install "wget" "" ""

# 3. 安装 MySQL
echo -e "${orange}③ 安装 MySQL 数据库...${reset}"
if ! dpkg -l | grep -q mysql-server; then
  # 安装时不提示密码
  DEBIAN_FRONTEND=noninteractive debconf-set-selections <<< "mysql-server mysql-server/root_password password ''"
  DEBIAN_FRONTEND=noninteractive debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ''"
  apt-get install -y mysql-server >> "$LOG_FILE" 2>&1
  [ $? -eq 0 ] && echo -e "${green}✓ MySQL 安装成功${reset}" || { echo -e "${red}✗ MySQL 安装失败${reset}"; exit 1; }
else
  echo -e "${yellow}⚠ MySQL 已安装${reset}"
fi

# 4. 安装邮件服务 Postfix/Dovecot
safe_install "postfix" "④" "安装 Postfix"
# 配置 Postfix 初始设定为 Internet Site 时, mail name 会提示域名，后续会修改
safe_install "postfix-mysql" "" ""
safe_install "dovecot-core" "⑤" "安装 Dovecot"
safe_install "dovecot-imapd" "" ""
safe_install "dovecot-pop3d" "" ""
safe_install "dovecot-mysql" "" ""

# 5. 安装 Apache/PHP
safe_install "apache2" "⑥" "安装 Apache"
safe_install "libapache2-mod-php" "" ""
safe_install "php" "" ""
safe_install "php-mysql" "" ""
safe_install "php-intl" "" ""
safe_install "php-curl" "" ""
safe_install "php-gd" "" ""
safe_install "php-mbstring" "" ""
safe_install "php-xml" "" ""
safe_install "php-zip" "" ""

# 6. 询问域名和管理员邮箱
read -p "$(echo -e "${yellow}✨ 请输入您的邮件域名 (如 example.com): ${reset}")" domain
echo -e "${blue}📝 输入为: ${green}$domain${reset}"
read -p "$(echo -e "${yellow}✨ 请输入服务器主机名 (如 mail.example.com): ${reset}")" hostname
echo -e "${blue}📝 输入为: ${green}$hostname${reset}"
read -p "$(echo -e "${yellow}✨ 请输入管理员邮箱 (如 admin@$domain): ${reset}")" admin_email
echo -e "${blue}📝 输入为: ${green}$admin_email${reset}"
read -p "$(echo -e "${yellow}✨ 请输入管理员密码: ${reset}")" -s admin_pass
echo -e "\n${blue}📝 输入为: ${green}[密码已隐藏]${reset}"

# 7. 配置 Postfix TLS 证书路径（稍后填写实际证书）
postconf -e "myhostname = $hostname"
postconf -e "mydomain = $domain"
postconf -e "myorigin = \$mydomain"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "mynetworks = 127.0.0.0/8"
postconf -e "inet_protocols = ipv4"
postconf -e "smtpd_tls_cert_file = /etc/letsencrypt/live/$hostname/fullchain.pem"
postconf -e "smtpd_tls_key_file = /etc/letsencrypt/live/$hostname/privkey.pem"
postconf -e "smtpd_use_tls = yes"
postconf -e "smtpd_tls_security_level = may"
postconf -e "smtpd_tls_auth_only = yes"
postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination"

# 8. 安装并申请 Let’s Encrypt 证书
echo -e "${orange}⑨ 安装Certbot并申请证书...${reset}"
safe_install "certbot" "" "安装 Certbot"
safe_install "python3-certbot-apache" "" ""
# 使用 Apache 插件自动配置 HTTPS（需保证 80 端口可访问）
certbot --apache -d $hostname -m "admin@$domain" --agree-tos --no-eff-email --redirect -n >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
  echo -e "${green}✓ SSL 证书申请成功${reset}"
else
  echo -e "${red}✗ SSL 证书申请失败${reset}"
fi

# 9. 配置 Dovecot 使用 SSL 证书
DOVECOT_CONF="/etc/dovecot/conf.d/10-ssl.conf"
echo "ssl = required" >> $DOVECOT_CONF
echo "ssl_cert = </etc/letsencrypt/live/$hostname/fullchain.pem" >> $DOVECOT_CONF
echo "ssl_key = </etc/letsencrypt/live/$hostname/privkey.pem" >> $DOVECOT_CONF

# 10. 配置防火墙 (UFW)，开放常用邮件端口
echo -e "${orange}⑩ 配置防火墙 (UFW)...${reset}"
safe_install "ufw" "" "安装 UFW"
ufw allow 22/tcp     # 保留 SSH 端口
ufw allow 25/tcp     # SMTP
ufw allow 587/tcp    # SMTP Submission
ufw allow 993/tcp    # IMAPS
ufw allow 443/tcp    # HTTPS
ufw --force enable
echo -e "${green}✓ 防火墙已启用并开放 25,587,993,443 端口${reset}"

# 11. 部署 Roundcube
install_roundcube

# 12. 初始化 Roundcube 数据库
init_roundcube_db

# 13. 创建数据库邮件用户（管理员）
echo -e "${orange}⑪ 创建管理员邮箱账户...${reset}"
encrypted=$(doveadm pw -s SHA512-CRYPT -p "$admin_pass")
mysql -uroot <<SQL
INSERT INTO virtual_domains (name) VALUES ('$domain') ON DUPLICATE KEY UPDATE id=id;
INSERT INTO virtual_users (domain_id, email, password) VALUES (
  (SELECT id FROM virtual_domains WHERE name='$domain'), 
  '$admin_email', '$encrypted'
);
SQL
echo -e "${green}✓ 管理员账号 $admin_email 已创建${reset}"

# 完成信息
draw_mid
echo -e "${green}✅ 安装完成！${reset}"
echo -e "${blue}🌍 访问地址: ${green}https://$hostname/roundcube${reset}"
echo -e "${blue}📧 管理员邮箱: ${green}$admin_email${reset}"
echo -e "${blue}🔑 MySQL root 密码: ${green}(空密码)${reset}"
draw_bottom

read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
