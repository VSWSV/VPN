#!/bin/bash

# 颜色定义
blue="\033[1;34m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
cyan="\033[1;36m"
magenta="\033[1;35m"
reset="\033[0m"

cecho() {
  local color=$1
  shift
  echo -e "${color}$*${reset}"
}

test_smtp() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 📧 SMTP测试${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请输入发件人邮箱: ${reset}")" from
  echo -e "${blue}📝 输入为: ${green}$from${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请输入收件人邮箱: ${reset}")" to
  echo -e "${blue}📝 输入为: ${green}$to${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请输入邮件主题: ${reset}")" subject
  echo -e "${blue}📝 输入为: ${green}$subject${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请输入邮件内容: ${reset}")" body
  echo -e "${blue}📝 输入为: ${green}$body${reset}"
  
  echo -e "${blue}📤 正在发送测试邮件...${reset}"
  echo "$body" | mail -s "$subject" -r "$from" "$to"
  
  if [ $? -eq 0 ]; then
    echo -e "${green}✅ 测试邮件已发送!${reset}"
  else
    echo -e "${red}✗ 邮件发送失败!${reset}"
  fi
  
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
  
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  test_menu
}

test_imap() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 📥 IMAP测试${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请输入邮箱地址: ${reset}")" email
  echo -e "${blue}📝 输入为: ${green}$email${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请输入密码: ${reset}")" -s password
  echo -e "\n${blue}📝 输入为: ${green}[密码已隐藏]${reset}"
  
  hostname=$(grep "myhostname" /etc/postfix/main.cf | awk -F "= " '{print $2}')
  
  echo -e "${blue}🔒 正在测试IMAP连接...${reset}"
  curl -k --url "imaps://$hostname" --user "$email:$password"
  
  if [ $? -eq 0 ]; then
    echo -e "${green}✅ IMAP连接成功!${reset}"
  else
    echo -e "${red}✗ IMAP连接失败!${reset}"
  fi
  
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
  
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  test_menu
}

test_webmail() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 🌐 Webmail测试${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  
  hostname=$(grep "myhostname" /etc/postfix/main.cf | awk -F "= " '{print $2}')
  echo -e "${blue}🌍 Webmail访问地址: ${yellow}https://$hostname/roundcube${reset}"
  echo -e "${blue}🖥️ 请使用浏览器访问上述地址测试Webmail功能${reset}"
  
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
  
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  test_menu
}

test_menu() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 🧪 邮件系统测试${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  echo -e "${green}① 测试SMTP发送${reset}"
  echo -e "${green}② 测试IMAP接收${reset}"
  echo -e "${green}③ 测试Webmail访问${reset}"
  echo -e "${green}④ 返回主菜单${reset}"
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请选择测试类型 [1-4]: ${reset}")" choice
  case $choice in
    1) test_smtp ;;
    2) test_imap ;;
    3) test_webmail ;;
    4) bash /root/VPN/menu/mail.sh ;;
    *) echo -e "${red}✗ 无效选择!${reset}"; sleep 1; test_menu ;;
  esac
}

test_menu
