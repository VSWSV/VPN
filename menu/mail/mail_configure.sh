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
  echo -e "                               ${orange}📬 邮局SSL证书申请器${reset}"
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

# 开始执行
clear
draw_header

# 检测Certbot是否存在
if ! command -v certbot &> /dev/null; then
  echo -e "${red}❌ 未检测到 Certbot！请先安装 Certbot。${reset}"
  echo -e "${yellow}可使用命令安装：apt install -y certbot${reset}"
  draw_footer
  exit 1
fi

# 输入要申请证书的主机名
read -p "$(echo -e "${yellow}▶ 请输入要申请SSL证书的主机名（如 mail.vswsv.com）：${reset}")" hostname

# 显示输入确认
echo -e "${blue}📝 输入的主机名为：${green}$hostname${reset}"

# 申请证书
echo -e "${yellow}⚙️ 正在为 ${hostname} 申请 SSL证书...${reset}"
systemctl stop apache2 nginx 2>/dev/null

certbot certonly --standalone -d "$hostname" --agree-tos --register-unsafely-without-email

systemctl start apache2 nginx 2>/dev/null

# 检查证书是否申请成功
if [ -f "/etc/letsencrypt/live/${hostname}/fullchain.pem" ]; then
  draw_footer
  echo -e "${green}✔️ 证书申请成功！${reset}"
  echo -e "${blue}📜 证书文件路径：${green}/etc/letsencrypt/live/${hostname}/fullchain.pem${reset}"
  echo -e "${blue}🔑 私钥文件路径：${green}/etc/letsencrypt/live/${hostname}/privkey.pem${reset}"
  echo -e "${blue}🌍 访问示例：${green}https://${hostname}/roundcube${reset}"
else
  draw_footer
  echo -e "${red}❌ 证书申请失败，请检查域名解析是否正确指向本机！${reset}"
fi

return_menu
