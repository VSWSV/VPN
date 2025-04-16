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

echo -e "                                  ${orange}🧰 网络-工具${reset}"

echo -e "${pink}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

echo -e "  ${yellow}❶${reset} ${green}查看本机 IP 地址${reset}               ${yellow}❷${reset} ${green}网络连通性测试${reset}               ${yellow}❸${reset} ${green}Ping 指定 IP${reset} "
echo -e "  ${yellow}❹${reset} ${green}查看端口使用情况${reset}               ${yellow}❺${reset} ${green}查看日志${reset}                     ${yellow}⓿${reset} ${red}返回主菜单${reset}"

echo -e "${pink}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

read -p "请输入选项编号： " opt

case $opt in
  1) bash /root/VPN/menu/network/check_ip.sh ;;
  2) bash /root/VPN/menu/network/ping_test.sh ;;
  3) bash /root/VPN/menu/network/ping_ip.sh ;;
  4) bash /root/VPN/menu/network/check_ports.sh ;;
  5) bash /root/VPN/menu/network/view_logs.sh ;;
  0) bash /root/VPN/menu.sh ;;
  *) echo -e "${red}❌ 无效输入${reset}" && read -p "请输入选项编号： " opt ;;
esac
