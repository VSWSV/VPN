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
magenta="\033[1;35m"
reset="\033[0m"

cecho() {
  local color=$1
  shift
  echo -e "${color}$*${reset}"
}

draw_header() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 📮 邮局系统升级${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

upgrade_step() {
  local step_name="$1"
  local upgrade_cmd="$2"
  cecho "$yellow" "▶ $step_name..."
  echo -ne "${blue}▷ 进度:${reset} "
  (eval "$upgrade_cmd" >> "$LOG_FILE" 2>&1) &
  pid=$!
  while ps -p $pid > /dev/null; do
    echo -n "."
    sleep 1
  done
  wait $pid
  if [ $? -eq 0 ]; then
    printf "\r${green}✓ $step_name完成${reset}\n"
    return 0
  else
    printf "\r${red}✗ $step_name失败${reset}\n"
    cecho "$yellow" "▶ 错误日志:"
    tail -n 10 "$LOG_FILE" | grep -Ei "error|fail|cp:|cannot|denied" | sed "s/error\|fail\|cp:\|cannot\|denied/${red}&${reset}/g"
    return 1
  fi
}

main_upgrade() {
  draw_header
  
  # ① 备份当前配置
  upgrade_step "① 备份当前配置" "cp -r /var/www/roundcube/config $INSTALL_DIR/backup_config_$(date +%Y%m%d)"
  
  # ② 升级Roundcube
  upgrade_step "② 下载最新版Roundcube" "wget -q --tries=3 --timeout=30 https://github.com/roundcube/roundcubemail/releases/download/1.6.4/roundcubemail-1.6.4-complete.tar.gz -O $INSTALL_DIR/roundcube_new.tar.gz"
  
  # ③ 解压新版本
  upgrade_step "③ 解压新版本" "mkdir -p $INSTALL_DIR/roundcube_new && tar -xzf $INSTALL_DIR/roundcube_new.tar.gz -C $INSTALL_DIR/roundcube_new --strip-components=1"
  
  # ④ 迁移配置
  upgrade_step "④ 迁移配置文件" "cp -r /var/www/roundcube/config/* $INSTALL_DIR/roundcube_new/config/ && cp /var/www/roundcube/composer.json $INSTALL_DIR/roundcube_new/"
  
  # ⑤ 替换旧版本
  upgrade_step "⑤ 替换旧版本" "rm -rf /var/www/roundcube && mv $INSTALL_DIR/roundcube_new /var/www/roundcube && chown -R www-data:www-data /var/www/roundcube"
  
  # ⑥ 升级系统组件
  upgrade_step "⑥ 升级系统组件" "apt update -y && apt upgrade -y postfix dovecot apache2 php"
  
  draw_footer
  
  cecho "$green" "✅ 升级完成！"
  
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  bash /root/VPN/menu/mail.sh
}

main_upgrade
