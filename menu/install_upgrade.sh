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

echo -e "                                   ${orange}🛠️ 安装-升级${reset}"

echo -e "${pink}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

echo -e "  ${yellow}❶${reset} ${green}全新安装${reset}                         ${yellow}❷${reset} ${green}升级组件${reset}                        ${yellow}❸${reset} ${green}检查依赖${reset}"
echo -e "  ${yellow}❹${reset} ${green}验证安装${reset}                         ${yellow}⓿${reset} ${red}返回主菜单${reset}"

echo -e "${pink}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

read -p "请输入选项编号： " opt

case $opt in
  1) bash /root/VPN/menu/install/full_install.sh ;;
  2) bash /root/VPN/menu/install/upgrade_components.sh ;;
  3) bash /root/VPN/menu/install/check_dependencies.sh ;;
  4) bash /root/VPN/menu/install/verify_installation.sh ;;
  0) bash /root/VPN/menu.sh ;;
  *) echo -e "${red}❌ 无效输入${reset}" && read -p "请输入选项编号： " opt ;;
esac
