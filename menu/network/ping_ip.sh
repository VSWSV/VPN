#!/bin/bash

cyan="\033[1;36m"
green="\033[1;32m"
red="\033[1;31m"
reset="\033[0m"

echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "                                  📡 Ping 指定 IP 地址"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

read -p "请输入 IP 地址：" ip && ping -c 4 $ip

echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
