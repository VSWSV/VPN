#!/bin/bash

INSTALL_DIR="/root/VPN/MAIL"
source $INSTALL_DIR/.mail_config 2>/dev/null

blue="\033[1;34m"; green="\033[1;32m"; yellow="\033[1;33m"; red="\033[1;31m"
orange="\033[38;5;214m"; cyan="\033[1;36m"; reset="\033[0m"

# Webmail 测试
test_webmail() {
  draw_top
  echo -e "${orange}                 🌐 Webmail访问测试            ${reset}"
  draw_mid
  echo -e "${yellow}① 请在浏览器中打开下列地址并登录测试: ${reset}"
  echo -e "${green}    https://mail.$DOMAIN/roundcube${reset}"
  draw_bottom
}

# IMAP 测试
test_imap() {
  draw_top
  echo -e "${orange}                 📥 IMAP协议测试                ${reset}"
  draw_mid
  read -p "$(echo -e "${yellow}✨ 请输入测试邮箱地址: ${reset}")" email
  read -p "$(echo -e "${yellow}✨ 请输入邮箱密码: ${reset}")" -s password
  echo
  echo -e "${yellow}① 测试 IMAPS 连接...${reset}"
  if command -v curl &>/dev/null; then
    curl --silent --insecure --url "imaps://$hostname/" --user "$email:$password" && \
      echo -e "${green}✓ IMAP 连接成功${reset}" || \
      echo -e "${red}✗ IMAP 连接失败${reset}"
  else
    echo -e "${red}✗ 未检测到 curl 工具，请安装后重试${reset}"
  fi
  draw_bottom
}

# SMTP 测试
test_smtp() {
  draw_top
  echo -e "${orange}                 📤 SMTP协议测试                ${reset}"
  draw_mid
  read -p "$(echo -e "${yellow}✨ 请输入发件邮箱: ${reset}")" from
  read -p "$(echo -e "${yellow}✨ 请输入收件邮箱: ${reset}")" to
  echo -e "${yellow}① 测试 SMTP 发送...${reset}"
  {
    sleep 1; echo "ehlo $hostname"
    sleep 1; echo "mail from:<$from>"
    sleep 1; echo "rcpt to:<$to>"
    sleep 1; echo "data"
    sleep 1; echo "Subject: SMTP测试邮件"
    sleep 1; echo "这是一封来自邮件服务器的测试邮件。"
    sleep 1; echo "."
    sleep 1; echo "quit"
  } | telnet $hostname 25
  echo -e "${yellow}② 检查日志:${reset}"
  tail -n 5 /var/log/mail.log | grep -i "$from"
  draw_bottom
}

# 全系统测试
full_test() {
  draw_top
  echo -e "${orange}                 🧪 邮件系统完整测试            ${reset}"
  draw_mid
  echo -e "${yellow}① 服务运行状态:${reset}"
  declare -A services=( ["Postfix"]="postfix" ["Dovecot"]="dovecot" ["Apache"]="apache2" ["MySQL"]="mysql" )
  for name in "${!services[@]}"; do
    status=$(systemctl is-active "${services[$name]}")
    [ "$status" = "active" ] && color="$green" || color="$red"
    echo -e "${blue}${name} 服务: ${color}${status}${reset}"
  done
  draw_mid
  echo -e "${yellow}② 端口开放检测:${reset}"
  nc -zv $hostname 25 &>/dev/null && echo -e "${green}✓ SMTP(25) 开放${reset}" || echo -e "${red}✗ SMTP(25) 未开放${reset}"
  nc -zv $hostname 587 &>/dev/null && echo -e "${green}✓ Submission(587) 开放${reset}" || echo -e "${red}✗ Submission(587) 未开放${reset}"
  nc -zv $hostname 993 &>/dev/null && echo -e "${green}✓ IMAPS(993) 开放${reset}" || echo -e "${red}✗ IMAPS(993) 未开放${reset}"
  draw_mid
  echo -e "${yellow}③ DNS MX 记录检测:${reset}"
  if dig +short mx $DOMAIN | grep -q "mail.$DOMAIN"; then
    echo -e "${green}✓ MX记录配置正确${reset}"
  else
    echo -e "${red}✗ MX记录配置错误${reset}"
  fi
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
