#!/bin/bash

# 颜色定义
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
purple="\033[1;35m"
cyan="\033[1;36m"
orange="\033[38;5;214m"
pink="\033[1;35m"
reset="\033[0m"

while true; do
  echo -e "${pink}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                                     ${orange}🗑️ 卸载${reset}"
  echo -e "${pink}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  echo -e "  ${yellow}❶${reset} ${green}卸载 HY2/VLESS 节点${reset}                                 ${yellow}❷${reset} ${green}卸载核心组件（sing-box）${reset}"
  echo -e "  ${yellow}❸${reset} ${red}完全卸载 VPN 系统${reset}                                   ${yellow}⓿${reset} ${red}返回主菜单${reset}"
  echo -e "${pink}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
  
  read -p "请输入选项编号： " opt
  case $opt in
    1) bash /root/VPN/menu/uninstall/uninstall_hy2_vless.sh; break ;;
    2) bash /root/VPN/menu/uninstall/uninstall_core.sh; break ;;
    3) bash /root/VPN/menu/uninstall/full_uninstall.sh; break ;;
    0) bash /root/VPN/menu.sh; break ;;
    *) echo -e "${red}❌ 无效输入，请重新选择！${reset}"; sleep 1 ;;
  esac
done
