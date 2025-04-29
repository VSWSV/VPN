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
    echo -e "  ${yellow}❶${reset} ${green}邮局系统安装${reset}                   ${yellow}❷${reset} ${green}邮局域名配置${reset}                  ${yellow}❸${reset} ${green}邮局账户管理${reset}"
    echo -e "  ${yellow}❹${reset} ${green}服务启停状态${reset}                   ${yellow}❺${reset} ${green}数据库控制板${reset}                  ${yellow}❻${reset} ${green}邮局系统测试${reset}"
    echo -e "  ${yellow}❼${reset} ${red}邮局系统卸载${reset}                   ${yellow}⓿${reset} ${red}返回主菜单${reset}"
    echo -e "${pink}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

while true; do
    show_menu
    read -p "请输入选项编号： " opt
    case $opt in
        1) bash /root/VPN/menu/mail/mail_install.sh
            break ;;
        2) bash /root/VPN/menu/mail/mail_configure.sh
            break ;;
        3) bash /root/VPN/menu/mail/mail_Account.sh
            break ;;
        4) bash /root/VPN/menu/mail/mail_khiav.sh
            break ;;
        5) bash /root/VPN/menu/mail/mail_database.sh
            break ;;
        6) bash /root/VPN/menu/mail/mail_test.sh
            break ;;
        7) bash /root/VPN/menu/mail/mail_uninstall.sh
            break ;;
        0) bash /root/VPN/menu.sh
            break ;;
        *) echo -e "${red}❌ 无效输入！${reset}"
            sleep 0.5 ;;
    esac
done
