#!/bin/bash

INSTALL_DIR="/root/VPN/MAIL"
LOG_FILE="$INSTALL_DIR/install.log"
mkdir -p "$INSTALL_DIR" >/dev/null 2>&1

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

draw_top
echo -e "${orange}                 ⬆️ 邮件系统升级               ${reset}"
draw_mid
echo -e "${yellow}① 更新系统并升级软件包...${reset}"
apt-get update >> "$LOG_FILE" 2>&1
apt-get upgrade -y >> "$LOG_FILE" 2>&1
if [ $? -eq 0 ]; then
  echo -e "${green}✓ 系统和软件包已更新${reset}"
else
  echo -e "${red}✗ 系统升级失败${reset}"
  exit 1
fi

draw_mid
echo -e "${yellow}② 升级 Postfix/Dovecot...${reset}"
systemctl stop postfix dovecot
DEBIAN_FRONTEND=noninteractive apt install --only-upgrade -y \
  postfix postfix-mysql \
  dovecot-core dovecot-imapd dovecot-pop3d dovecot-mysql >> "$LOG_FILE" 2>&1
systemctl start postfix dovecot
if [ $? -eq 0 ]; then
  echo -e "${green}✓ 邮件服务已升级${reset}"
else
  echo -e "${red}✗ 邮件服务升级失败${reset}"
  exit 1
fi

# 检查 Roundcube 是否有新版本
current_rc_version=$(roundcube/SQL/mysql.initial.sql | grep -m1 version | awk -F'-' '{print $2}' 2>/dev/null)
latest_rc_version=$(curl -s https://api.github.com/repos/roundcube/roundcubemail/releases/latest | grep tag_name | cut -d '"' -f4 | sed 's/v//g')
if [ "$current_rc_version" != "$latest_rc_version" ]; then
  draw_mid
  echo -e "${yellow}③ 升级 Roundcube Webmail...${reset}"
  backup_dir="/var/www/roundcube_backup_$(date +%Y%m%d)"
  cp -r /var/www/roundcube "$backup_dir"
  wget -q https://github.com/roundcube/roundcubemail/releases/download/${latest_rc_version}/roundcubemail-${latest_rc_version}-complete.tar.gz -O /tmp/roundcube.tar.gz
  tar -xzf /tmp/roundcube.tar.gz -C /var/www
  rm -rf /var/www/roundcube
  mv /var/www/roundcubemail-${latest_rc_version} /var/www/roundcube
  cp -r "$backup_dir"/config/* /var/www/roundcube/config/
  cp "$backup_dir"/composer.json /var/www/roundcube/
  chown -R www-data:www-data /var/www/roundcube
  echo -e "${green}✓ Roundcube 已升级到 ${latest_rc_version}${reset}"
else
  echo -e "${green}✔ Roundcube 已是最新版本${reset}"
fi

draw_mid
echo -e "${green}✅ 升级完成！${reset}"
draw_bottom

read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
