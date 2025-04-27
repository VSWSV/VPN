#!/bin/bash

# 颜色定义
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
cyan="\033[1;36m"
orange="\033[38;5;214m"
reset="\033[0m"

# 边框函数
draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                               ${orange}📬 邮局DNS记录设置引导器${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 获取公网IPv4
get_public_ip() {
  ipv4=$(curl -s4 ip.sb)
  echo "$ipv4"
}

# 获取发信邮箱（假设在系统中已经配置）
get_mail_address() {
  # 这里假设邮箱格式是 mail@vswsv.com，按需求调整
  mail_address="mail@vswsv.com"
  echo "$mail_address"
}

# 返回上级菜单
return_menu() {
  read -p "$(echo -e "💬 ${cyan}按回车键返回数据库管理菜单...${reset}")" dummy
  bash /root/VPN/menu/mail.sh
}

# 获取公网IPv4并开始配置DNS记录
clear
draw_header

# 获取IPv4地址
ipv4=$(get_public_ip)
echo -e "${blue}📝 当前服务器公网IPv4：${green}$ipv4${reset}"

# 输入主域名
read -p "$(echo -e "${yellow}▶ 请输入主域名（如：vswsv.com）：${reset}")" domain
echo -e "${blue}📝 输入的主域名为：${green}$domain${reset}"

# 获取发信邮箱地址
mail_address=$(get_mail_address)

# A记录提示
echo -e "${yellow}① ${green}A记录： mail -> $ipv4${reset}"
# MX记录提示
echo -e "${yellow}② ${green}MX记录： @ -> mail.${domain} 优先级 10${reset}"
# SPF记录提示
echo -e "${yellow}③ ${green}TXT记录（SPF）： @ -> v=spf1 mx ~all${reset}"
# DMARC记录提示
echo -e "${yellow}④ ${green}TXT记录（DMARC，可选）： _dmarc -> v=DMARC1; p=none; rua=mailto:${mail_address}${reset}"
# DKIM记录提示
echo -e "${yellow}⑤ ${green}TXT记录（DKIM，后续生成）${reset}"

# 提示TTL建议
echo -e "${blue}🔧 推荐TTL（生效时间）: 600秒${reset}"

# 返回菜单
draw_footer
return_menu
