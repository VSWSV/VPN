#!/bin/bash

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
  echo -e "${cyan}╔$(printf '═%.0s' {1..78})╗${reset}"
}
draw_mid() {
  echo -e "${cyan}╠$(printf '═%.0s' {1..78})╣${reset}"
}
draw_bottom() {
  echo -e "${cyan}╚$(printf '═%.0s' {1..78})╝${reset}"
}

service_status() {
  draw_top
  echo -e "${orange}                 🚦 服务运行状态                ${reset}"
  draw_mid
  declare -A services=(
    ["Postfix"]="postfix"
    ["Dovecot"]="dovecot"
    ["Apache"]="apache2"
    ["MySQL"]="mysql"
  )
  for name in "${!services[@]}"; do
    status=$(systemctl is-active ${services[$name]})
    [ "$status" = "active" ] && color="$green" || color="$red"
    echo -e "${blue}${name} 服务: ${color}${status}${reset}"
  done
  draw_bottom
}

restart_services() {
  draw_top
  echo -e "${orange}                 🔄 重启所有服务                ${reset}"
  draw_mid
  systemctl restart postfix dovecot apache2 mysql
  echo -e "${green}✅ 所有服务已重启${reset}"
  draw_bottom
}

# 服务控制菜单
main_menu() {
  while true; do
    draw_top
    echo -e "${orange}                 🎛️ 服务控制菜单               ${reset}"
    draw_mid
    echo -e "${green}① 查看服务状态${reset}"
    echo -e "${green}② 重启所有服务${reset}"
    echo -e "${green}⓪ 返回主菜单${reset}"
    draw_mid
    read -p "$(echo -e "${yellow}✨ 请选择操作: ${reset}")" choice
    case $choice in
      1) service_status ;;
      2) restart_services ;;
      0) break ;;
      *) echo -e "${red}✗ 无效选择!${reset}"; sleep 1 ;;
    esac
  done
}

main_menu
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
