#!/bin/bash

green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
orange="\033[38;5;214m"
pink="\033[1;35m"
reset="\033[0m"

show_menu() {
    clear
    echo -e "${pink}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "                                 ${orange}🌐 配置-设置${reset}"
    echo -e "${pink}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "  ${yellow}❶${reset} ${green}配置 HY2${reset}                                                         ${yellow}❷${reset} ${green}配置 VES${reset}"
    echo -e "  ${yellow}❸${reset} ${green}部署隧道${reset}                                                         ${yellow}❹${reset} ${green}隧道服务${reset}"
    echo -e "  ${yellow}⓿${reset} ${red}返回主菜单${reset}"
    echo -e "${pink}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

while true; do
    show_menu
    read -p "请输入选项编号： " opt
    case $opt in
        1) bash /root/VPN/menu/config/config_hy2.sh
            break ;;
        2) bash /root/VPN/menu/config/config_vless.sh
            break ;;
        3) bash /root/VPN/menu/config/config_tunnel.sh
            break ;; 
        4) bash /root/VPN/menu/config/config_serve.sh
            break ;;
        0) bash /root/VPN/menu.sh
            break ;;
        *) echo -e "${red}❌ 无效输入！${reset}"
            sleep 0.5 ;;
    esac
done    
