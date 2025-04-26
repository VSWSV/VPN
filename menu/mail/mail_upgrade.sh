#!/bin/bash

INSTALL_DIR="/root/VPN/MAIL"
LOG_FILE="$INSTALL_DIR/upgrade.log"
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
echo -e "${orange}🔧 检查并修复APT锁和未完成安装...${reset}"
if [ -f /var/lib/dpkg/lock ] || [ -f /var/lib/dpkg/lock-frontend ]; then
  echo -e "${yellow}检测到APT锁定文件，尝试解除...${reset}"
  killall apt apt-get &>/dev/null
  rm -f /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock /var/lib/apt/lists/lock
  dpkg --configure -a &>/dev/null
  echo -e "${green}✓ 已清理锁并修复${reset}"
fi

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

need_upgrade=false

check_updates() {
  draw_top
  echo -e "${orange}🔍 检查可用升级                ${reset}"
  draw_mid

  echo -e "${yellow}① 检查系统更新...${reset}"
  wait_for_apt
  apt update &>> "$LOG_FILE"
  updates=$(apt list --upgradable 2>/dev/null | grep -v "^Listing...")
  if [ -z "$updates" ]; then
    echo -e "${green}✓ 没有可用的系统升级${reset}"
    need_upgrade=false
  else
    echo -e "${yellow}发现以下可用升级：${reset}"
    echo "$updates" | sed "s/^/${green}➤ ${reset}/"
    need_upgrade=true
  fi

  draw_mid
  echo -e "${yellow}② 检查Roundcube更新...${reset}"
  current_rc_version=$(grep "version =" /var/www/roundcube/index.php | head -1 | cut -d\" -f2)
  latest_rc_version=$(curl -s https://api.github.com/repos/roundcube/roundcubemail/releases/latest | grep tag_name | cut -d '"' -f4)
  if [ "$current_rc_version" != "$latest_rc_version" ]; then
    echo -e "${yellow}发现Roundcube新版本：${green}$latest_rc_version${reset}"
    echo -e "${yellow}当前版本：${green}$current_rc_version${reset}"
    need_upgrade=true
  else
    echo -e "${green}✓ Roundcube已是最新版${reset}"
  fi

  draw_bottom
}

upgrade_system() {
  draw_top
  echo -e "${orange}⬆️ 执行系统升级                ${reset}"
  draw_mid

  echo -e "${yellow}① 升级系统组件...${reset}"
  wait_for_apt
  DEBIAN_FRONTEND=noninteractive apt upgrade -y &>> "$LOG_FILE"
  if [ $? -eq 0 ]; then
    echo -e "${green}✓ 系统组件升级完成${reset}"
  else
    echo -e "${red}✗ 系统组件升级失败${reset}"
    tail -n 5 "$LOG_FILE" | sed "s/error/${red}&${reset}/gi"
    return 1
  fi

  draw_mid
  echo -e "${yellow}② 升级邮件服务...${reset}"
  systemctl stop postfix dovecot
  wait_for_apt
  DEBIAN_FRONTEND=noninteractive apt install --only-upgrade -y \
    postfix postfix-mysql \
    dovecot-core dovecot-imapd dovecot-pop3d dovecot-mysql &>> "$LOG_FILE"
  systemctl start postfix dovecot

  if [ $? -eq 0 ]; then
    echo -e "${green}✓ 邮件服务升级完成${reset}"
  else
    echo -e "${red}✗ 邮件服务升级失败${reset}"
    return 1
  fi

  draw_bottom
}

upgrade_roundcube() {
  draw_top
  echo -e "${orange}⬆️ 升级 Roundcube               ${reset}"
  draw_mid

  echo -e "${yellow}① 备份当前配置...${reset}"
  backup_dir="/var/www/roundcube_$(date +%Y%m%d)"
  cp -r /var/www/roundcube "$backup_dir"
  echo -e "${green}✓ 配置已备份到：${backup_dir}${reset}"

  draw_mid
  echo -e "${yellow}② 下载新版 Roundcube...${reset}"
  wget -q https://github.com/roundcube/roundcubemail/releases/download/${latest_rc_version}/roundcubemail-${latest_rc_version}-complete.tar.gz -O /tmp/roundcube_new.tar.gz

  draw_mid
  echo -e "${yellow}③ 解压新版本...${reset}"
  tar -xzf /tmp/roundcube_new.tar.gz -C /tmp
  rm -rf /var/www/roundcube
  mv /tmp/roundcubemail-${latest_rc_version} /var/www/roundcube

  draw_mid
  echo -e "${yellow}④ 恢复配置...${reset}"
  cp -r "$backup_dir"/config/* /var/www/roundcube/config/
  cp "$backup_dir"/composer.json /var/www/roundcube/
  chown -R www-data:www-data /var/www/roundcube

  draw_mid
  echo -e "${green}✓ Roundcube升级完成！新版本：${latest_rc_version}${reset}"
  draw_bottom
}

main() {
  check_updates
  if ! $need_upgrade; then
    draw_top
    echo -e "${green}            ✅ 所有组件均已是最新版本，无需升级            ${reset}"
    draw_bottom
    read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
    bash /root/VPN/menu/mail.sh
    exit 0
  fi

  read -p "$(echo -e "${yellow}✨ 是否执行升级？(y/n): ${reset}")" confirm
  if [[ ! $confirm =~ ^[Yy]$ ]]; then
    bash /root/VPN/menu/mail.sh
    exit 0
  fi

  upgrade_system
  if [ "$current_rc_version" != "$latest_rc_version" ]; then
    upgrade_roundcube
  fi

  draw_top
  echo -e "${green}            ✅ 所有可用升级已完成            ${reset}"
  draw_bottom
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  bash /root/VPN/menu/mail.sh
}

main
