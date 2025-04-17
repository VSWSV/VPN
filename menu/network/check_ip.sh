#!/bin/bash

cyan="\033[1;36m"
green="\033[1;32m"
red="\033[1;31m"
reset="\033[0m"

echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "                                  🌐 当前主机 IP 信息"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

ip a | grep -v lo | grep inet

echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
