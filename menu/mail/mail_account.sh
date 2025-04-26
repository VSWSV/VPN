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
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
}
draw_mid() {
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}
draw_bottom() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 添加邮箱账户
add_account() {
  draw_top
  echo -e "${orange}                 📨 创建邮箱账户                ${reset}"
  draw_mid
  read -p "$(echo -e "${yellow}✨ 请输入邮箱地址 (如 user@$DOMAIN): ${reset}")" email
  echo -e "${blue}📝 输入为: ${green}$email${reset}"
  read -p "$(echo -e "${yellow}✨ 请输入密码: ${reset}")" -s password
  echo -e "\n${blue}📝 输入为: ${green}[密码已隐藏]${reset}"
  encrypted=$(doveadm pw -s SHA512-CRYPT -p "$password")
  domain_part=${email#*@}
  mysql -u$DB_USER -p$DB_PASS $DB_NAME <<SQL
INSERT INTO virtual_domains (name) VALUES ('$domain_part') ON DUPLICATE KEY UPDATE id=id;
INSERT INTO virtual_users (domain_id, email, password) VALUES (
  (SELECT id FROM virtual_domains WHERE name='$domain_part'),
  '$email', '$encrypted'
);
SQL
  draw_mid
  echo -e "${green}✅ 账户创建成功!${reset}"
  echo -e "${blue}📧 邮箱地址: ${green}$email${reset}"
  draw_bottom
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

# 设置全局收件（Catch-All）
set_catchall() {
  draw_top
  echo -e "${orange}                 🌐 设置全局收件                ${reset}"
  draw_mid
  read -p "$(echo -e "${yellow}✨ 请输入接收邮箱 (如 catchall@$DOMAIN): ${reset}")" catchall
  echo -e "${blue}📝 输入为: ${green}$catchall${reset}"
  mysql -u$DB_USER -p$DB_PASS $DB_NAME <<SQL
INSERT INTO virtual_aliases (domain_id, source, destination)
VALUES (
  (SELECT id FROM virtual_domains WHERE name='$DOMAIN'),
  '@$DOMAIN',
  '$catchall'
);
SQL
  draw_mid
  echo -e "${green}✅ 全局收件设置成功!${reset}"
  echo -e "${blue}所有发送到 ${green}*@$DOMAIN${blue} 的邮件将转发到 ${green}$catchall${reset}"
  draw_bottom
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

# 查看账户列表
show_accounts() {
  draw_top
  echo -e "${orange}                 📋 邮箱账户列表                ${reset}"
  draw_mid
  mysql -u$DB_USER -p$DB_PASS $DB_NAME -e "SELECT email AS '邮箱账号', LEFT(password,10) AS '密码哈希前10位' FROM virtual_users;" 2>/dev/null \
    || echo -e "${red}暂无邮箱账户${reset}"
  draw_bottom
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

main_menu() {
  while true; do
    draw_top
    echo -e "${orange}                 📮 账户管理菜单               ${reset}"
    draw_mid
    echo -e "${green}① 创建邮箱账户${reset}"
    echo -e "${green}② 设置全局收件${reset}"
    echo -e "${green}③ 查看账户列表${reset}"
    echo -e "${green}0 返回主菜单${reset}"
    draw_mid
    read -p "$(echo -e "${yellow}✨ 请选择操作: ${reset}")" choice
    case $choice in
      1) add_account ;;
      2) set_catchall ;;
      3) show_accounts ;;
      0) break ;;
      *) echo -e "${red}✗ 无效选择!${reset}"; sleep 1 ;;
    esac
  done
}

main_menu
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
