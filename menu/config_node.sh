#!/bin/bash

green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
purple="\033[1;35m"
cyan="\033[1;36m"
orange="\033[38;5;214m"
pink="\033[1;35m"
reset="\033[0m"

echo -e "${pink}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"

echo -e "                                 ${orange}🌐 节点配置菜单${reset}"

echo -e "${pink}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

echo -e "  ${yellow}❶${reset} ${green}配置 HY2${reset}                                                           ${yellow}❷${reset} ${green}配置 VES${reset}"
echo -e "  ${yellow}❸${reset} ${green}配置全部${reset}                                                           ${yellow}⓿${reset} ${red}退出${reset}"

echo -e "${pink}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

read -p "请输入选项编号： " opt

case $opt in
  1) bash /root/VPN/menu/config/config_hy2.sh ;;
  2) bash /root/VPN/menu/config/config_vless.sh ;;
  3) bash /root/VPN/menu/config/config_all.sh ;;
  0) bash /root/VPN/menu.sh ;;
  *) echo -e "${red}❌ 无效输入${reset}" && read -p "请输入选项编号： " opt ;;
esac
