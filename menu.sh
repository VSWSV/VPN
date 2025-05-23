#!/bin/bash

green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
purple="\033[1;35m"
cyan="\033[1;36m"
orange="\033[38;5;214m"
reset="\033[0m"

show_menu() {
  clear
  echo -e "${blue}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                                   ${orange}🧰 超级工具箱${reset}"
  echo -e "${blue}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  echo -e "  ${yellow}❶${reset} ${green}安装-升级${reset}                       ${yellow}❷${reset} ${green}启动-服务${reset}                       ${yellow}❸${reset} ${green}停止-服务${reset}"
  echo -e "  ${yellow}❹${reset} ${green}配置-设置${reset}                       ${yellow}❺${reset} ${green}邮局-系统${reset}                       ${yellow}❻${reset} ${green}网络-工具${reset}"
  echo -e "  ${yellow}❼${reset} ${red}卸载${reset}                                                              ${yellow}⓿${reset} ${red}退出${reset}"
  echo -e "${blue}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

while true; do
  show_menu
  read -p "请输入选项编号： " opt
  case "$opt" in
    1) bash /root/VPN/menu/install_upgrade.sh
    break ;;
    2) bash /root/VPN/menu/start_service.sh
    break ;;
    3) bash /root/VPN/menu/stop_service.sh
    break ;;
    4) bash /root/VPN/menu/config_node.sh
    break;;
    5) bash /root/VPN/menu/mail.sh
    break ;;
    6) bash /root/VPN/menu/network_tools.sh
    break ;;
    7) bash /root/VPN/menu/uninstall.sh 
    break ;;
    0) echo -e "${green}正在退出${reset}"
    sleep 0.5
    exit 0
    break ;;
    *) 
    echo -e "${red}❌ 无效输入！${reset}"
    sleep 0.5 ;;
  esac
done

