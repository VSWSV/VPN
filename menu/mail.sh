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

show_menu() {
    clear
    echo -e "${pink}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "                                  ${orange}✉️ 邮局-系统${reset}"
    echo -e "${pink}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "  ${yellow}❶${reset} ${green}安装${reset}                   ${yellow}❷${reset} ${green}清理系统缓存${reset}                  ${yellow}❸${reset} ${green}释放内存缓存${reset}"
    echo -e "  ${yellow}❹${reset} ${green}查看错误日志${reset}                   ${yellow}❺${reset} ${green}清理临时文件${reset}                  ${yellow}❻${reset} ${green}清除代理缓存${reset}"
    echo -e "  ${yellow}❼${reset} ${green}清理所有日志${reset}                   ${yellow}❽${reset} ${green}查看磁盘空间${reset}                  ${yellow}⓿${reset} ${red}返回主菜单${reset}"
    echo -e "${pink}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

while true; do
    show_menu
    read -p "请输入选项编号： " opt
    case $opt in
        1) bash /root/VPN/menu/mail/install_mail.sh
            break ;;
        2) bash /root/VPN/menu/maintain/clean_system_cache.sh
            break ;;
        3) bash /root/VPN/menu/maintain/release_mem.sh
           break ;;
        4) bash /root/VPN/menu/maintain/show_errors.sh
            break ;;
        5) bash /root/VPN/menu/maintain/temp_clean.sh
            break ;;
        6) bash /root/VPN/menu/maintain/clear_proxy_cache.sh
            break ;;
        7) bash /root/VPN/menu/maintain/clean_all_logs.sh
            break ;;
        8) bash /root/VPN/menu/maintain/disk_check.sh
            break ;;
        0) bash /root/VPN/menu.sh
            break ;;
        *) echo -e "${red}❌ 无效输入！${reset}"
            sleep 0.5 ;;
    esac
done
