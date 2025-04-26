#!/bin/bash

# ==============================================
# 邮件系统完整安装脚本
# 包含：Postfix/Dovecot/Apache/Roundcube/MySQL
# 版本：7.0
# 特点：无备份文件、无垃圾文件、全自动安装
# ==============================================

INSTALL_DIR="/root/VPN/MAIL"
LOG_FILE="$INSTALL_DIR/install.log"
mkdir -p "$INSTALL_DIR" && chmod 700 "$INSTALL_DIR"
> "$LOG_FILE"

# 颜色定义
blue="\033[1;34m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
cyan="\033[1;36m"
reset="\033[0m"

# 边框函数
draw_top() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
}
draw_mid() {
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}
draw_bottom() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 安装组件函数
install_pkg() {
  local pkg="$1"
  local step="$2"
  local desc="$3"
  
  echo -e "${orange}${step} ${desc}...${reset}"
  if dpkg -l | grep -q "^ii  $pkg "; then
    echo -e "${yellow}⚠ 已安装: ${green}$pkg${yellow} 版本: ${green}$(dpkg -s $pkg | grep Version | cut -d' ' -f2)${reset}"
    echo -e "${blue}✓ 跳过安装${reset}"
    return 0
  else
    apt-get install -y "$pkg" >> "$LOG_FILE" 2>&1
    [ $? -eq 0 ] && echo -e "${green}✓ 安装成功${reset}" || { echo -e "${red}✗ 安装失败${reset}"; tail -n 3 "$LOG_FILE"; exit 1; }
  fi
}

# 主安装流程
draw_top
echo -e "${orange}                  📮 邮局系统安装                 ${reset}"
draw_mid

# 1. 更新系统
echo -e "${orange}① 更新软件包列表...${reset}"
apt-get update >> "$LOG_FILE" 2>&1
[ $? -eq 0 ] && echo -e "${green}✓ 更新完成${reset}" || { echo -e "${red}✗ 更新失败${reset}"; exit 1; }

# 2. 安装必要工具
install_pkg "tree" "②" "安装依赖工具"
install_pkg "curl" "" ""
install_pkg "wget" "" ""

# 3. 安装MySQL
echo -e "${orange}③ 安装MySQL数据库...${reset}"
if ! dpkg -l | grep -q mysql-server; then
  debconf-set-selections <<< "mysql-server mysql-server/root_password password temp_p@ssw0rd"
  debconf-set-selections <<< "mysql-server mysql-server/root_password_again password temp_p@ssw0rd"
  apt-get install -y mysql-server >> "$LOG_FILE" 2>&1
  
  # 安全设置
  mysql -uroot -ptemp_p@ssw0rd <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '';
FLUSH PRIVILEGES;
EOF
  
  echo -e "${green}✓ MySQL安装完成${reset}"
else
  echo -e "${yellow}⚠ MySQL已安装${reset}"
fi

# 4. 安装邮件服务
install_pkg "postfix" "④" "安装Postfix"
install_pkg "postfix-mysql" "" ""
install_pkg "dovecot-core" "⑤" "安装Dovecot"
install_pkg "dovecot-imapd" "" ""
install_pkg "dovecot-pop3d" "" ""
install_pkg "dovecot-mysql" "" ""

# 5. 安装Web服务
install_pkg "apache2" "⑥" "安装Apache"
install_pkg "libapache2-mod-php" "" ""
install_pkg "php" "⑦" "安装PHP组件"
install_pkg "php-mysql" "" ""
install_pkg "php-intl" "" ""
install_pkg "php-curl" "" ""
install_pkg "php-gd" "" ""
install_pkg "php-mbstring" "" ""
install_pkg "php-xml" "" ""
install_pkg "php-zip" "" ""

# 6. 安装Roundcube
echo -e "${orange}⑧ 部署Roundcube...${reset}"
if [ -d "/var/www/roundcube" ]; then
  echo -e "${yellow}⚠ 删除旧版Roundcube...${reset}"
  rm -rf /var/www/roundcube
fi

wget -q https://github.com/roundcube/roundcubemail/releases/download/1.6.3/roundcubemail-1.6.3-complete.tar.gz -O /tmp/roundcube.tar.gz
tar -xzf /tmp/roundcube.tar.gz -C /var/www
mv /var/www/roundcubemail-1.6.3 /var/www/roundcube
chown -R www-data:www-data /var/www/roundcube
rm -f /tmp/roundcube.tar.gz
[ $? -eq 0 ] && echo -e "${green}✓ 部署完成${reset}" || { echo -e "${red}✗ 部署失败${reset}"; exit 1; }

# 7. 初始化数据库
echo -e "${orange}⑨ 初始化邮件数据库...${reset}"
mysql -uroot <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS roundcubedb DEFAULT CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS 'roundcube'@'localhost' IDENTIFIED BY 'roundcube_password';
GRANT ALL PRIVILEGES ON roundcubedb.* TO 'roundcube'@'localhost';
FLUSH PRIVILEGES;
USE roundcubedb;
SOURCE /var/www/roundcube/SQL/mysql.initial.sql;
MYSQL_SCRIPT
[ $? -eq 0 ] && echo -e "${green}✓ 数据库初始化完成${reset}" || { echo -e "${red}✗ 数据库初始化失败${reset}"; exit 1; }

# 完成提示
draw_mid
echo -e "${orange}🔍 服务状态检查:${reset}"
systemctl is-active postfix &>/dev/null && echo -e "${green}✓ Postfix运行正常${reset}" || echo -e "${red}✗ Postfix未运行${reset}"
systemctl is-active dovecot &>/dev/null && echo -e "${green}✓ Dovecot运行正常${reset}" || echo -e "${red}✗ Dovecot未运行${reset}"
systemctl is-active apache2 &>/dev/null && echo -e "${green}✓ Apache运行正常${reset}" || echo -e "${red}✗ Apache未运行${reset}"
systemctl is-active mysql &>/dev/null && echo -e "${green}✓ MySQL运行正常${reset}" || echo -e "${red}✗ MySQL未运行${reset}"

draw_mid
echo -e "${green}✅ 安装全部完成！"
echo -e "${blue}🔑 MySQL root密码已设置为空"
echo -e "${blue}📧 Roundcube数据库用户: roundcube"
echo -e "${blue}🔐 Roundcube数据库密码: roundcube_password"
echo -e "${blue}🌍 访问地址: https://您的服务器IP/roundcube${reset}"
draw_bottom

read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
