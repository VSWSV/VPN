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
function draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                               ${orange}📬 邮局系统配置向导${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

function return_menu() {
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  bash /root/VPN/menu/mail.sh
}

# 自动检测IP
ipv4=$(curl -s4 ip.sb)
ipv6=$(curl -s6 ip.sb)

while true; do
  clear
  draw_header

  echo -e "  ${yellow}①${reset} ${green}建数据库${reset}        ${yellow}②${reset} ${green}设主机名域名${reset}     ${yellow}③${reset} ${green}DNS引导${reset}"
  echo -e "  ${yellow}④${reset} ${green}SSL证书${reset}          ${yellow}⑤${reset} ${green}设Postfix${reset}        ${yellow}⑥${reset} ${green}设Dovecot${reset}"
  echo -e "   ${yellow}⓪${reset} ${red}返回主菜单${reset}"

  draw_footer

  read -p "请输入选项编号：" opt
  case $opt in
    1)
      clear
      draw_header
      echo -e "${cyan}▶ 请输入数据库名称：${reset}"
      read dbname
      echo -e "${cyan}▶ 请输入数据库用户名(不要用root)：${reset}"
      read dbuser

      if [[ "$dbuser" == "root" ]]; then
        echo -e "${red}❌ 不允许使用root作为普通数据库账户，请重新输入！${reset}"
        return_menu
      fi

      echo -e "${cyan}▶ 请输入数据库用户密码：${reset}"
      read dbpass
      echo -e "${cyan}▶ 请再次确认数据库用户密码：${reset}"
      read dbpass_confirm

      if [ "$dbpass" != "$dbpass_confirm" ]; then
        echo -e "${red}❌ 两次输入的密码不一致！${reset}"
        return_menu
      fi

      mysql -u root -p <<EOF
CREATE DATABASE IF NOT EXISTS ${dbname} DEFAULT CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}';
GRANT ALL PRIVILEGES ON ${dbname}.* TO '${dbuser}'@'localhost';
FLUSH PRIVILEGES;
EOF

      echo -e "${green}✅ 数据库 ${dbname} 和用户 ${dbuser} 创建成功！${reset}"

      echo -e "${cyan}▶ 当前数据库列表:${reset}"
      mysql -u root -p -e "SHOW DATABASES;"

      cd /root/VPN/MAIL/roundcube
      mysql -u ${dbuser} -p${dbpass} ${dbname} < SQL/mysql.initial.sql

      echo -e "${cyan}▶ 表结构导入完成，当前表列表:${reset}"
      mysql -u ${dbuser} -p${dbpass} -e "USE ${dbname}; SHOW TABLES;"

      echo -e "${green}✅ 完整建库导表完成！${reset}"
      echo -e "${blue}🔗 连接方式：mysql -u ${dbuser} -p ${dbname}${reset}"
      return_menu
      ;;

    # 其余选项 (2/3/4/5/6/0) 保持之前内容，不改动...

    *)
      echo -e "${red}❌ 无效输入，请重新选择！${reset}"
      sleep 1
      ;;
  esac
done
