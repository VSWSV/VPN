#!/bin/bash

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

# 修复残留锁和未完成安装
echo -e "\n${orange}🔧 检查并修复APT锁和未完成安装...${reset}"
if [ -f /var/lib/dpkg/lock ] || [ -f /var/lib/dpkg/lock-frontend ]; then
  echo -e "${yellow}检测到APT锁定文件，尝试解除...${reset}"
  killall apt apt-get &>/dev/null
  rm -f /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock /var/lib/apt/lists/lock
  dpkg --configure -a &>/dev/null
  echo -e "${green}✓ 已清理锁并修复${reset}"
fi

# APT锁检测和超时处理
wait_for_apt() {
  local timeout=60
  while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    if (( timeout <= 0 )); then
      echo -e "${yellow}APT锁等待超时，强制解除...${reset}"
      killall apt apt-get &>/dev/null
      rm -f /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock /var/lib/apt/lists/lock
      dpkg --configure -a &>/dev/null
      break
    fi
    sleep 1
    timeout=$((timeout - 1))
  done
}

# 边框函数
draw_top() {
  echo -e "${cyan}╔$(printf '═%.0s' {1..78})╗${reset}"
}
draw_mid() {
  echo -e "${cyan}╠$(printf '═%.0s' {1..78})╣${reset}"
}
draw_bottom() {
  echo -e "${cyan}╚$(printf '═%.0s' {1..78})╝${reset}"
}

# 安全安装函数
safe_install() {
  local pkg=$1
  local step=$2
  local desc=$3

  echo -e "${orange}${step} ${desc}...${reset}"
  if dpkg -l | grep -q "^ii  $pkg "; then
    echo -e "${yellow}⚠ 已安装: ${green}$pkg${reset}"
    return 0
  fi

  wait_for_apt
  apt-get install -y "$pkg" >> "$LOG_FILE" 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${green}✓ 安装成功${reset}"
    return 0
  else
    echo -e "${red}✗ 安装失败${reset}"
    tail -n 3 "$LOG_FILE"
    return 1
  fi
}

# 部署Roundcube
install_roundcube() {
  echo -e "${orange}⑦ 部署Roundcube...${reset}"
  # 清理旧版本
  [ -d "/var/www/roundcube" ] && rm -rf /var/www/roundcube

  # 下载并部署新版本
  latest=$(curl -s https://api.github.com/repos/roundcube/roundcubemail/releases/latest | grep tag_name | cut -d '"' -f4)
  if wget -q https://github.com/roundcube/roundcubemail/releases/download/$latest/roundcubemail-$latest-complete.tar.gz -O /tmp/roundcube.tar.gz && \
     tar -xzf /tmp/roundcube.tar.gz -C /var/www && \
     mv /var/www/roundcubemail-$latest /var/www/roundcube && \
     chown -R www-data:www-data /var/www/roundcube; then
    rm -f /tmp/roundcube.tar.gz
    echo -e "${green}✓ 部署成功${reset}"
    return 0
  else
    echo -e "${red}✗ 部署失败${reset}"
    return 1
  fi
}

# 初始化邮件数据库
init_database() {
  echo -e "${orange}⑧ 初始化邮件数据库...${reset}"
  # 检查表是否存在
  if mysql -uroot roundcubedb -e "SHOW TABLES LIKE 'session'" 2>/dev/null | grep -q "session"; then
    echo -e "${yellow}⚠ 数据库已初始化，跳过${reset}"
    return 0
  fi

  # 创建数据库和用户
  mysql -uroot <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS roundcubedb DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS 'roundcube'@'localhost' IDENTIFIED BY 'roundcube_password';
GRANT ALL PRIVILEGES ON roundcubedb.* TO 'roundcube'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

  # 导入表结构
  mysql -uroot roundcubedb < /var/www/roundcube/SQL/mysql.initial.sql 2>&1 | grep -v "already exists"
  if [ \$? -eq 0 ]; then
    echo -e "${green}✓ 数据库初始化完成${reset}"
    return 0
  else
    echo -e "${red}✗ 数据库初始化失败${reset}"
    return 1
  fi
}

# 主安装流程
draw_top
echo -e "${orange}                  📮 邮件系统安装                 ${reset}"
draw_mid

# 1. 系统更新
echo -e "${orange}① 更新软件包列表...${reset}"
wait_for_apt
apt-get update >> "$LOG_FILE" 2>&1
[ \$? -eq 0 ] && echo -e "${green}✓ 更新完成${reset}" || { echo -e "${red}✗ 更新失败${reset}"; exit 1; }

# 2. 安装必要工具
safe_install "tree" "②" "安装系统工具"
safe_install "curl" "" ""
safe_install "wget" "" ""

# 3. 安装MySQL
echo -e "${orange}③ 安装MySQL数据库...${reset}"
if ! dpkg -l | grep -q mysql-server; then
  debconf-set-selections <<< "mysql-server mysql-server/root_password password ''"
  debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ''"
  wait_for_apt
  apt-get install -y mysql-server >> "$LOG_FILE" 2>&1
  [ \$? -eq 0 ] && echo -e "${green}✓ 安装成功${reset}" || { echo -e "${red}✗ 安装失败${reset}"; exit 1; }
else
  echo -e "${yellow}⚠ MySQL已安装${reset}"
fi

# 4. 安装Postfix
echo -e "${orange}④ 安装Postfix...${reset}"
export DEBIAN_FRONTEND=noninteractive
export DEBIAN_PRIORITY=critical
hostname_fqdn=$(hostname -f)
debconf-set-selections <<< "postfix postfix/mailname string $hostname_fqdn"
debconf-set-selections <<< "postfix postfix/main_mailer_type select Internet Site"
if ! dpkg -l | grep -q postfix; then
  wait_for_apt
  apt-get install -y postfix postfix-mysql >> "$LOG_FILE" 2>&1
  [ \$? -eq 0 ] && echo -e "${green}✓ Postfix 安装成功${reset}" || { echo -e "${red}✗ Postfix 安装失败${reset}"; exit 1; }
else
  echo -e "${yellow}⚠ Postfix已安装${reset}"
fi

# 5. 安装Dovecot
safe_install "dovecot-core" "⑤" "安装Dovecot"
safe_install "dovecot-imapd" "" ""
safe_install "dovecot-pop3d" "" ""
safe_install "dovecot-mysql" "" ""

# 6. 安装Web服务
safe_install "apache2" "⑥" "安装Apache"
safe_install "libapache2-mod-php" "" ""
safe_install "php" "" "安装PHP"
safe_install "php-mysql" "" ""
safe_install "php-intl" "" ""
safe_install "php-curl" "" ""
safe_install "php-gd" "" ""
safe_install "php-mbstring" "" ""
safe_install "php-xml" "" ""
safe_install "php-zip" "" ""

# 7. 部署Roundcube
install_roundcube || exit 1

# 8. 初始化数据库
init_database || exit 1

draw_mid
echo -e "${green}✅ 安装完成！${reset}"
echo -e "${blue}🔑 MySQL root密码: 空（建议安装后修改）${reset}"
echo -e "${blue}📧 Roundcube数据库: ${green}roundcubedb${reset}"
echo -e "${blue}👤 数据库用户: ${green}roundcube${reset}"
echo -e "${blue}🔐 数据库密码: ${green}roundcube_password${reset}"
echo -e "${blue}🌐 Roundcube访问: ${green}https://$hostname_fqdn/roundcube${reset}"
draw_bottom

read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
