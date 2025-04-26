#!/bin/bash

INSTALL_DIR="/root/VPN/MAIL"
source $INSTALL_DIR/.mail_config 2>/dev/null

# 颜色定义
blue="\033[1;34m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
cyan="\033[1;36m"
reset="\033[0m"

# 边框函数
draw_top() {
  echo -e "${cyan}╔$(printf '═%.0s' {1..78})╗${reset}"
}
draw_mid() {
  echo -e "${cyan}╠$(printf '═%.0s' {1..78})╣${reset}"
}
draw_bottom() {
  echo -e "${cyan}╚$(printf '═%.0s' {1..78})╝${reset}"
}

# Webmail访问测试
test_webmail() {
  draw_top
  echo -e "${orange}                 🌐 Webmail访问测试            ${reset}"
  draw_mid
  if curl -k --silent "https://$HOSTNAME/roundcube" >/dev/null; then
    echo -e "${green}✓ 成功访问 ${cyan}https://$HOSTNAME/roundcube${reset}"
  else
    echo -e "${red}✗ 无法访问 ${cyan}https://$HOSTNAME/roundcube${reset}"
  fi
  draw_bottom
}

# IMAP协议测试
test_imap() {
  draw_top
  echo -e "${orange}                 📥 IMAP协议测试                ${reset}"
  draw_mid
  read -p "$(echo -e "${yellow}✨ 请输入邮箱 (如 user@$DOMAIN): ${reset}")" email
  read -p "$(echo -e "${yellow}✨ 请输入密码: ${reset}")" -s password
  echo -e "\n${blue}📝 输入为: ${green}[密码已隐藏]${reset}"
  echo -e "${yellow}① 测试 IMAP 登录...${reset}"
  if curl -s -k --url "imaps://$HOSTNAME" --user "$email:$password" >/dev/null; then
    echo -e "${green}✓ IMAP 登录成功${reset}"
  else
    echo -e "${red}✗ IMAP 登录失败${reset}"
  fi
  draw_bottom
}

# SMTP协议测试
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

# 完整系统测试
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
  nc -zv $HOSTNAME 25 &>/dev/null && echo -e "${green}✓ SMTP(25)端口开放${reset}" ||
    echo -e "${red}✗ SMTP(25)端口未开放${reset}"
  nc -zv $HOSTNAME 587 &>/dev/null && echo -e "${green}✓ Submission(587)端口开放${reset}" ||
    echo -e "${red}✗ Submission(587)端口未开放${reset}"
  nc -zv $HOSTNAME 993 &>/dev/null && echo -e "${green}✓ IMAPS(993)端口开放${reset}" ||
    echo -e "${red}✗ IMAPS(993)端口未开放${reset}"

  draw_mid
  echo -e "${yellow}③ 测试DNS记录:${reset}"
  dig +short mx $DOMAIN | grep -q "mail.$DOMAIN" && \
    echo -e "${green}✓ MX记录配置正确${reset}" || \
    echo -e "${red}✗ MX记录配置错误${reset}"

  draw_bottom
}

# 测试菜单
main_menu() {
  while true; do
    draw_top
    echo -e "${orange}                 🧪 邮件系统测试菜单           ${reset}"
    draw_mid
    echo -e "${green}① Webmail访问测试${reset}"
    echo -e "${green}② IMAP协议测试${reset}"
    echo -e "${green}③ SMTP协议测试${reset}"
    echo -e "${green}④ 完整系统测试${reset}"
    echo -e "${green}⓪ 返回主菜单${reset}"
    draw_mid
    read -p "$(echo -e "${yellow}✨ 请选择测试项目: ${reset}")" choice
    case $choice in
      1) test_webmail ;;
      2) test_imap ;;
      3) test_smtp ;;
      4) full_test ;;
      0) break ;;
      *) echo -e "${red}✗ 无效选择!${reset}"; sleep 1 ;;
    esac
    read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
  done
}

main_menu
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
