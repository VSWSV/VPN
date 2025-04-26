#!/bin/bash

INSTALL_DIR="/root/VPN/MAIL"
LOG_FILE="$INSTALL_DIR/install.log"
mkdir -p "$INSTALL_DIR" && chmod 700 "$INSTALL_DIR"
> "$LOG_FILE"

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

show_dir_structure() {
  echo -e "${orange}📦 安装目录结构:${reset}"
  if command -v tree &>/dev/null; then
    echo -e "${blue}"
    tree -L 2 --noreport "$INSTALL_DIR"
    echo -e "${reset}"
    echo -e "${blue}$(find "$INSTALL_DIR" -type d | wc -l) 个目录${reset} ${green}$(find "$INSTALL_DIR" -type f | wc -l) 个文件${reset}"
  else
    echo -e "${blue}"
    ls -lhp "$INSTALL_DIR" | grep -v "^total"
    echo -e "${reset}"
    echo -e "${blue}$(find "$INSTALL_DIR" -type d | wc -l) 个目录${reset} ${green}$(find "$INSTALL_DIR" -type f | wc -l) 个文件${reset}"
  fi
}

install_step() {
  local step_num=$1
  local step_name=$2
  local install_cmd=$3
  
  echo -e "${orange}${step_num} ${step_name}...${reset}"
  echo -ne "${blue}▶ 进度:${reset} "
  
  (eval "$install_cmd" >> "$LOG_FILE" 2>&1) &
  local pid=$!
  while ps -p $pid > /dev/null; do
    echo -n "."
    sleep 0.5
  done
  wait $pid
  
  if [ $? -eq 0 ]; then
    echo -e "\r${green}✓ ${step_num} ${step_name}完成${reset}"
  else
    echo -e "\r${red}✗ ${step_num} ${step_name}失败${reset}"
    echo -e "${yellow}▶ 错误日志:${reset}"
    tail -n 5 "$LOG_FILE" | sed "s/error\|fail\|cannot/${red}&${reset}/gi"
    exit 1
  fi
}

draw_top
echo -e "${orange}                  📮 邮局系统安装                 ${reset}"
draw_mid

install_step "①" "安装依赖工具" "apt update && apt install -y tree curl wget"
install_step "②" "安装邮件服务" "apt install -y postfix postfix-mysql dovecot-core dovecot-imapd dovecot-pop3d dovecot-mysql"
install_step "③" "安装Web服务" "apt install -y apache2 libapache2-mod-php php php-mysql php-intl php-curl"
install_step "④" "部署Roundcube" "wget -q https://github.com/roundcube/roundcubemail/releases/download/1.6.3/roundcubemail-1.6.3-complete.tar.gz -O /tmp/roundcube.tar.gz && tar -xzf /tmp/roundcube.tar.gz -C /var/www && mv /var/www/roundcubemail-1.6.3 /var/www/roundcube && chown -R www-data:www-data /var/www/roundcube"

draw_mid
show_dir_structure
draw_mid

echo -e "${orange}🔍 服务状态检查:${reset}"
systemctl is-active postfix &>/dev/null && echo -e "${green}✓ Postfix运行正常${reset}" || echo -e "${red}✗ Postfix未运行${reset}"
systemctl is-active dovecot &>/dev/null && echo -e "${green}✓ Dovecot运行正常${reset}" || echo -e "${red}✗ Dovecot未运行${reset}"
systemctl is-active apache2 &>/dev/null && echo -e "${green}✓ Apache运行正常${reset}" || echo -e "${red}✗ Apache未运行${reset}"

draw_bottom

read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
