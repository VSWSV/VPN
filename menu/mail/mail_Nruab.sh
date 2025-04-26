#!/bin/bash

INSTALL_DIR="/root/VPN/MAIL"
LOG_FILE="$INSTALL_DIR/install.log"
mkdir -p "$INSTALL_DIR" && chmod 700 "$INSTALL_DIR"
> "$LOG_FILE"

# 颜色定义
blue="\033[1;34m"; green="\033[1;32m"; yellow="\033[1;33m"; red="\033[1;31m"
orange="\033[38;5;214m"; cyan="\033[1;36m"; reset="\033[0m"

# 边框函数
draw_top() { echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"; }
draw_mid() { echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"; }
draw_bottom() { echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"; }

# 安全安装函数
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
    tail -n 10 "$LOG_FILE"
    exit 1
  fi
}

# 安装Roundcube
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

# 初始化Roundcube数据库
init_roundcube_db() {
  echo -e "${orange}⑧ 初始化 Roundcube 数据库...${reset}"
  mysql -uroot <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS roundcubedb DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS 'roundcube'@'localhost' IDENTIFIED BY 'roundcube_password';
GRANT ALL PRIVILEGES ON roundcubedb.* TO 'roundcube'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
  mysql -uroot roundcubedb < /var/www/roundcube/SQL/mysql.initial.sql 2>&1 | grep -v "already exists"
  echo -e "${green}✓ Roundcube数据库初始化完成${reset}"
}

# 主安装流程
draw_top
echo -e "${orange}                    📮 邮局系统安装                 ${reset}"
draw_mid

# 1. 更新软件包列表
echo -e "${orange}① 更新软件包列表...${reset}"
apt-get update >> "$LOG_FILE" 2>&1
[ $? -eq 0 ] && echo -e "${green}✓ 更新完成${reset}" || { echo -e "${red}✗ 更新失败${reset}"; exit 1; }

# 2. 安装基础工具
safe_install "tree" "②" "安装系统工具"
safe_install "curl" "" ""
safe_install "wget" "" ""

# 3. 安装MySQL
echo -e "${orange}③ 安装MySQL数据库...${reset}"
if ! dpkg -l | grep -q mysql-server; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y mysql-server >> "$LOG_FILE" 2>&1
  [ $? -eq 0 ] && echo -e "${green}✓ MySQL 安装成功${reset}" || { echo -e "${red}✗ MySQL 安装失败${reset}"; exit 1; }
else
  echo -e "${yellow}⚠ MySQL已安装${reset}"
fi

# 4. 安装Postfix (防止卡住)
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical
apt-get install -y debconf-utils >> "$LOG_FILE" 2>&1
read -p "$(echo -e "${yellow}✨ 请输入您的服务器主机名 (如 mail.example.com): ${reset}")" hostname
echo "postfix postfix/mailname string $hostname" | debconf-set-selections
echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
draw_mid
echo -e "${orange}④ 安装 Postfix...${reset}"
if timeout 300s apt-get install -y postfix postfix-mysql >> "$LOG_FILE" 2>&1; then
  echo -e "${green}✓ Postfix 安装成功${reset}"
else
  echo -e "${red}✗ Postfix 安装失败或超时${reset}"
  tail -n 10 "$LOG_FILE"
  exit 1
fi

# 5. 安装Dovecot
safe_install "dovecot-core" "⑤" "安装 Dovecot"
safe_install "dovecot-imapd" "" ""
safe_install "dovecot-pop3d" "" ""
safe_install "dovecot-mysql" "" ""

# 6. 安装Apache+PHP
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

# 7. 安装Certbot并申请SSL
safe_install "certbot" "⑦" "安装Certbot"
safe_install "python3-certbot-apache" "" ""
draw_mid
echo -e "${orange}⑧ 申请Let’s Encrypt证书...${reset}"
read -p "$(echo -e "${yellow}✨ 请输入您的邮件域名 (如 example.com): ${reset}")" domain
certbot --apache -d $hostname -m admin@$domain --agree-tos --no-eff-email --redirect -n >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
  echo -e "${green}✓ SSL证书申请成功${reset}"
else
  echo -e "${red}✗ SSL证书申请失败${reset}"
fi

# 8. 配置防火墙
draw_mid
echo -e "${orange}⑨ 配置防火墙（UFW）...${reset}"
safe_install "ufw" "" "安装UFW"
ufw allow 22/tcp
ufw allow 25/tcp
ufw allow 587/tcp
ufw allow 993/tcp
ufw allow 443/tcp
ufw --force enable
echo -e "${green}✓ 防火墙配置完成${reset}"

# 9. 部署Roundcube
install_roundcube

# 10. 初始化Roundcube数据库
init_roundcube_db

# 11. 创建管理员邮箱账户
draw_mid
echo -e "${orange}⑩ 创建管理员邮箱账户...${reset}"
read -p "$(echo -e "${yellow}✨ 请输入管理员邮箱 (如 postmaster@$domain): ${reset}")" admin_email
read -p "$(echo -e "${yellow}✨ 请输入管理员密码: ${reset}")" -s admin_pass
echo -e "\n${blue}📝 已输入密码${reset}"
encrypted=$(doveadm pw -s SHA512-CRYPT -p "$admin_pass")
mysql -uroot <<SQL
INSERT INTO virtual_domains (name) VALUES ('$domain') ON DUPLICATE KEY UPDATE id=id;
INSERT INTO virtual_users (domain_id, email, password) VALUES (
  (SELECT id FROM virtual_domains WHERE name='$domain'),
  '$admin_email', '$encrypted'
);
SQL
echo -e "${green}✓ 管理员账户创建完成${reset}"

# 安装结束信息
draw_mid
echo -e "${green}✅ 邮局系统安装完成！${reset}"
echo -e "${blue}🌍 Webmail访问: ${green}https://$hostname/roundcube${reset}"
echo -e "${blue}📧 管理员邮箱: ${green}$admin_email${reset}"
echo -e "${blue}🔐 Roundcube数据库账户: roundcube 密码: roundcube_password${reset}"
draw_bottom

read -p "$(echo -e \"💬 ${cyan}按回车键返回...${reset}\")" dummy
bash /root/VPN/menu/mail.sh
