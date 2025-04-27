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
  echo -e "                               ${orange}📬 邮局域名与主机名配置器${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 返回上级菜单
return_menu() {
  read -p "$(echo -e "💬 ${cyan}按回车键返回数据库管理菜单...${reset}")" dummy
  bash /root/VPN/menu/mail.sh
}

# 开始配置
clear
draw_header

# 输入主域名
read -p "$(echo -e "${yellow}▶ 请输入主域名（例如 vswsv.com）：${reset}")" domain
# 输入主机名
read -p "$(echo -e "${yellow}▶ 请输入主机名（例如 mail.vswsv.com）：${reset}")" hostname

# 显示输入确认
echo -e "${blue}📝 输入的主域名为：${green}$domain${reset}"
echo -e "${blue}📝 输入的主机名为：${green}$hostname${reset}"

# 开始配置系统主机名
echo -e "${yellow}⚙️ 配置系统主机名...${reset}"
hostnamectl set-hostname "$hostname"

# 更新/etc/hostname
echo "$hostname" > /etc/hostname

# 更新/etc/hosts（确保 localhost 和 新域名都映射）
sed -i '/127.0.1.1/d' /etc/hosts
echo "127.0.0.1   localhost" > /etc/hosts
echo "127.0.1.1   $hostname $domain" >> /etc/hosts

# 配置 Postfix
echo -e "${yellow}⚙️ 配置Postfix服务...${reset}"
postconf -e "myhostname = $hostname"
postconf -e "mydomain = $domain"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"

# 配置 Dovecot证书路径
echo -e "${yellow}⚙️ 配置Dovecot服务...${reset}"
dovecot_ssl_conf="/etc/dovecot/conf.d/10-ssl.conf"

# 清理旧证书设置
sed -i '/ssl_cert =/d' "$dovecot_ssl_conf"
sed -i '/ssl_key =/d' "$dovecot_ssl_conf"

# 添加新证书路径（默认 Let's Encrypt 路径）
echo "ssl_cert = </etc/letsencrypt/live/$hostname/fullchain.pem" >> "$dovecot_ssl_conf"
echo "ssl_key = </etc/letsencrypt/live/$hostname/privkey.pem" >> "$dovecot_ssl_conf"

# 完成
draw_footer
echo -e "${green}✔️ 域名与主机名配置成功！${reset}"
echo -e "${blue}🌍 主机名：${green}$hostname${reset}"
echo -e "${blue}🌍 邮局访问入口示例：https://${green}$hostname/roundcube${reset}"

return_menu
