#!/bin/bash

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

show_status() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 🚦 服务状态${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  
  # Postfix状态
  postfix_status=$(systemctl is-active postfix)
  [ "$postfix_status" = "active" ] && postfix_color="$green" || postfix_color="$red"
  echo -e "${blue}📭 Postfix (SMTP): ${postfix_color}$postfix_status${reset}"
  
  # Dovecot状态
  dovecot_status=$(systemctl is-active dovecot)
  [ "$dovecot_status" = "active" ] && dovecot_color="$green" || dovecot_color="$red"
  echo -e "${blue}📥 Dovecot (IMAP/POP3): ${dovecot_color}$dovecot_status${reset}"
  
  # Apache状态
  apache_status=$(systemctl is-active apache2)
  [ "$apache_status" = "active" ] && apache_color="$green" || apache_color="$red"
  echo -e "${blue}🌐 Apache (Web服务): ${apache_color}$apache_status${reset}"
  
  # MySQL状态
  mysql_status=$(systemctl is-active mysql)
  [ "$mysql_status" = "active" ] && mysql_color="$green" || mysql_color="$red"
  echo -e "${blue}🗃️ MySQL (数据库): ${mysql_color}$mysql_status${reset}"
  
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
  
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  control_menu
}

start_services() {
  echo -e "${blue}🔄 正在启动所有邮件服务...${reset}"
  systemctl start postfix dovecot apache2 mysql
  echo -e "${green}✅ 所有邮件服务已启动${reset}"
  sleep 1
  show_status
}

stop_services() {
  echo -e "${blue}🛑 正在停止所有邮件服务...${reset}"
  systemctl stop postfix dovecot apache2 mysql
  echo -e "${orange}⏸️ 所有邮件服务已停止${reset}"
  sleep 1
  show_status
}

restart_services() {
  echo -e "${blue}🔄 正在重启所有邮件服务...${reset}"
  systemctl restart postfix dovecot apache2 mysql
  echo -e "${green}🔄 所有邮件服务已重启${reset}"
  sleep 1
  show_status
}

control_menu() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 🎛️ 服务控制菜单${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  echo -e "${green}① 启动所有邮件服务${reset}"
  echo -e "${green}② 停止所有邮件服务${reset}"
  echo -e "${green}③ 重启所有邮件服务${reset}"
  echo -e "${green}④ 查看服务状态${reset}"
  echo -e "${green}⑤ 返回主菜单${reset}"
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请选择操作 [1-5]: ${reset}")" choice
  case $choice in
    1) start_services ;;
    2) stop_services ;;
    3) restart_services ;;
    4) show_status ;;
    5) bash /root/VPN/menu/mail.sh ;;
    *) echo -e "${red}✗ 无效选择!${reset}"; sleep 1; control_menu ;;
  esac
}

control_menu
