#!/bin/bash

INSTALL_DIR="/root/VPN/MAIL"
CONFIG_FILE="$INSTALL_DIR/.mail_config"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

blue="\033[1;34m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
cyan="\033[1;36m"
reset="\033[0m"

draw_top() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
}
draw_mid() {
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}
draw_bottom() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

test_webmail() {
  draw_top
  echo -e "${orange}                 🌐 Webmail访问测试              ${reset}"
  draw_mid
  
  if [ -z "$HOSTNAME" ]; then
    echo -e "${red}✗ 未检测到主机名配置，请先运行域名配置脚本${reset}"
    draw_bottom
    return 1
  fi
  
  echo -e "${green}① Webmail访问地址:${reset}"
  echo -e "${blue}https://$HOSTNAME/roundcube${reset}"
  
  echo -e "${green}② 管理员测试账户:${reset}"
  echo -e "${blue}postmaster@$DOMAIN${reset}"
  
  echo -e "${green}③ 测试步骤:${reset}"
  echo -e "${yellow}1. 使用浏览器访问上述地址"
  echo -e "2. 用管理员账户登录"
  echo -e "3. 检查能否正常收发邮件${reset}"
  
  draw_mid
  echo -e "${yellow}🔍 服务状态检查:${reset}"
  systemctl is-active apache2 &>/dev/null && echo -e "${green}✓ Apache运行正常${reset}" || echo -e "${red}✗ Apache未运行${reset}"
  
  draw_bottom
}

test_imap() {
  draw_top
  echo -e "${orange}                 📥 IMAP协议测试                ${reset}"
  draw_mid
  
  read -p "$(echo -e "${yellow}✨ 请输入测试邮箱地址: ${reset}")" email
  read -p "$(echo -e "${yellow}✨ 请输入邮箱密码: ${reset}")" -s password
  echo
  
  echo -e "${yellow}① 测试IMAP连接...${reset}"
  if command -v curl &>/dev/null; then
    curl -k --url "imaps://$HOSTNAME" --user "$email:$password" && \
    echo -e "${green}✓ IMAP连接成功${reset}" || \
    echo -e "${red}✗ IMAP连接失败${reset}"
  else
    echo -e "${yellow}➤ 使用telnet测试IMAP:${reset}"
    {
      sleep 1; echo "a1 LOGIN $email $password"
      sleep 1; echo "a2 LIST \"\" \"*\""
      sleep 1; echo "a3 LOGOUT"
    } | telnet $HOSTNAME 993 | grep -i "OK"
  fi
  
  draw_bottom
}

test_smtp() {
  draw_top
  echo -e "${orange}                 📤 SMTP协议测试                ${reset}"
  draw_mid
  
  read -p "$(echo -e "${yellow}✨ 请输入发件邮箱: ${reset}")" from
  read -p "$(echo -e "${yellow}✨ 请输入收件邮箱: ${reset}")" to
  
  echo -e "${yellow}① 测试SMTP发送...${reset}"
  {
    sleep 1; echo "ehlo $HOSTNAME"
    sleep 1; echo "mail from:<$from>"
    sleep 1; echo "rcpt to:<$to>"
    sleep 1; echo "data"
    sleep 1; echo "Subject: SMTP测试邮件"
    sleep 1; echo "This is a test email from your mail server."
    sleep 1; echo "."
    sleep 1; echo "quit"
  } | telnet $HOSTNAME 25
  
  echo -e "${yellow}② 检查日志:${reset}"
  tail -n 5 /var/log/mail.log | grep -i "$from"
  
  draw_bottom
}

full_test() {
  draw_top
  echo -e "${orange}                 🧪 邮件系统完整测试            ${reset}"
  draw_mid
  
  echo -e "${yellow}① 测试服务运行状态:${reset}"
  declare -A services=(
    ["Postfix"]="postfix"
    ["Dovecot"]="dovecot"
    ["Apache"]="apache2"
    ["MySQL"]="mysql"
  )
  for name in "${!services[@]}"; do
    status=$(systemctl is-active ${services[$name]})
    [ "$status" = "active" ] && color="$green" || color="$red"
    echo -e "${blue}${name}服务: ${color}${status}${reset}"
  done
  
  draw_mid
  echo -e "${yellow}② 测试端口开放情况:${reset}"
  nc -zv $HOSTNAME 25 &>/dev/null && echo -e "${green}✓ SMTP(25)端口开放${reset}" || echo -e "${red}✗ SMTP(25)端口未开放${reset}"
  nc -zv $HOSTNAME 587 &>/dev/null && echo -e "${green}✓ Submission(587)端口开放${reset}" || echo -e "${red}✗ Submission(587)端口未开放${reset}"
  nc -zv $HOSTNAME 993 &>/dev/null && echo -e "${green}✓ IMAPS(993)端口开放${reset}" || echo -e "${red}✗ IMAPS(993)端口未开放${reset}"
  
  draw_mid
  echo -e "${yellow}③ 测试DNS记录:${reset}"
  dig +short mx $DOMAIN | grep -q "mail.$DOMAIN" && \
    echo -e "${green}✓ MX记录配置正确${reset}" || \
    echo -e "${red}✗ MX记录配置错误${reset}"
  
  draw_bottom
}

main_menu() {
  while true; do
    draw_top
    echo -e "${orange}                 🧪 邮件系统测试菜单           ${reset}"
    draw_mid
    
    echo -e "${green}① Webmail访问测试${reset}"
    echo -e "${green}② IMAP协议测试${reset}"
    echo -e "${green}③ SMTP协议测试${reset}"
    echo -e "${green}④ 完整系统测试${reset}"
    echo -e "${green}⑤ 返回主菜单${reset}"
    draw_mid
    
    read -p "$(echo -e "${yellow}✨ 请选择测试项目: ${reset}")" choice
    
    case $choice in
      1) test_webmail ;;
      2) test_imap ;;
      3) test_smtp ;;
      4) full_test ;;
      5) break ;;
      *) echo -e "${red}✗ 无效选择!${reset}"; sleep 1 ;;
    esac
    
    read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
  done
}

main_menu
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
