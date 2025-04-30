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
    echo -e "                                      ${orange}🗑️ 卸载${reset}"
    echo -e "${pink}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "  ${yellow}❶${reset} ${green}卸载 HY2/VLESS 节点${reset}                                 ${yellow}❷${reset} ${green}卸载核心组件（sing-box）${reset}"
    echo -e "  ${yellow}❸${reset} ${red}完全卸载 VPN 系统${reset}                                   ${yellow}⓿${reset} ${red}返回主菜单${reset}"
    echo -e "${pink}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

confirm_action() {
    local action=$1
    local script=$2
    while true; do
        echo -e "${red}⚠️ 警告：这将${action}！[Y/N]${reset}"
        read confirm
        case $confirm in
            [yY]) bash "$script"
                break ;;
            [nN]|"") echo -e "${yellow}操作已取消${reset}"
                break ;;
            *) echo -e "${red}❌ 无效输入，请输入[Y/N]${reset}"
                ;;
        esac
    done
}

while true; do
    show_menu
    read -p "请输入选项编号：" opt
    case $opt in
        1) confirm_action "卸载 HY2/VLESS 节点" "/root/VPN/menu/uninstall/uninstall_hy2_vless.sh"
            break ;;
        2) confirm_action "卸载核心组件（sing-box）" "/root/VPN/menu/uninstall/uninstall_core.sh"
            break ;;
        3) confirm_action "完全卸载 VPN 系统" "/root/VPN/menu/uninstall/full_uninstall.sh"
            break ;;
        0) bash /root/VPN/menu.sh
            break ;;
        *) echo -e "${red}❌ 无效输入！${reset}"
            sleep 0.5 ;;
    esac
done
