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
  echo -e "                               ${orange}📬 MariaDB数据库管理器${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

return_menu() {
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  bash /root/VPN/menu/mail.sh
}

# 检查MySQL/MariaDB是否安装
if ! command -v mysql >/dev/null 2>&1; then
  echo -e "${red}❌ 未检测到MySQL/MariaDB，无法继续！${reset}"
  return_menu
fi

# 检查MySQL/MariaDB服务是否运行
if ! systemctl is-active --quiet mysql; then
  echo -e "${red}❌ MySQL/MariaDB服务未运行，请先启动！${reset}"
  return_menu
fi

while true; do
  clear
  draw_header

  echo -e "  ${yellow}①${reset} ${green}创建数据库/用户${reset}         ${yellow}②${reset} ${green}删除数据库${reset}         ${yellow}③${reset} ${green}查看数据库/表${reset}"
  echo -e "  ${yellow}④${reset} ${green}修改root密码${reset}           ${yellow}⑤${reset} ${green}调整数据库容量${reset}       ${yellow}⓪${reset} ${red}返回主菜单${reset}"

  draw_footer

  read -p "请输入选项编号：" opt
  case $opt in
    1)
      clear
      draw_header
      echo -e "ℹ️ 请输入要创建的数据库名称："
      read dbname
      echo -e "ℹ️ 请输入要创建的数据库用户名："
      read dbuser
      if [[ "$dbuser" == "root" ]]; then
        echo -e "${red}❌ 不允许使用root作为普通数据库账户！${reset}"
        return_menu
      fi
      echo -e "ℹ️ 请输入数据库用户密码："
      read -s dbpass
      draw_footer

      echo -e "ℹ️ 请确认，即将用root账户创建数据库和用户..."
      mysql -u root -p <<EOF
CREATE DATABASE IF NOT EXISTS \`${dbname}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}';
GRANT ALL PRIVILEGES ON \`${dbname}\`.* TO '${dbuser}'@'localhost';
FLUSH PRIVILEGES;
EOF

      if [ $? -eq 0 ]; then
        echo -e "${green}✔️ 数据库 ${dbname} 和用户 ${dbuser} 创建成功！${reset}"
      else
        echo -e "${red}❌ 创建失败！${reset}"
      fi
      return_menu
      ;;
    2)
      clear
      draw_header
      echo -e "ℹ️ 请输入要删除的数据库名称："
      read dbname_del
      draw_footer
      echo -e "⚠️ 确认要删除数据库 ${dbname_del} 吗？此操作不可逆！(y/n)"
      read confirm
      if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        mysql -u root -p -e "DROP DATABASE IF EXISTS \`${dbname_del}\`;"
        if [ $? -eq 0 ]; then
          echo -e "${green}✔️ 数据库 ${dbname_del} 删除成功！${reset}"
        else
          echo -e "${red}❌ 删除失败！${reset}"
        fi
      else
        echo -e "${red}❌ 已取消删除操作。${reset}"
      fi
      return_menu
      ;;
    3)
      clear
      draw_header
      echo -e "ℹ️ 当前服务器上的数据库列表："
      mysql -u root -p -e "SHOW DATABASES;"
      echo -e "ℹ️ 如果想查看某个数据库的表，请输入数据库名称："
      read show_db
      draw_footer
      mysql -u root -p -e "USE \`${show_db}\`; SHOW TABLES;"
      return_menu
      ;;
    4)
      clear
      draw_header
      echo -e "ℹ️ 正在修改MySQL root密码..."
      echo -e "ℹ️ 请输入新密码："
      read -s newrootpass
      echo -e "ℹ️ 请再次确认新密码："
      read -s newrootpass2
      if [ "$newrootpass" != "$newrootpass2" ]; then
        echo -e "${red}❌ 两次密码不一致！${reset}"
        return_menu
      fi
      draw_footer
      mysql -u root -p <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${newrootpass}';
FLUSH PRIVILEGES;
EOF
      if [ $? -eq 0 ]; then
        echo -e "${green}✔️ root密码修改成功！请牢记新密码。${reset}"
      else
        echo -e "${red}❌ 修改失败！${reset}"
      fi
      return_menu
      ;;
    5)
      clear
      draw_header
      echo -e "ℹ️ 快捷调整数据库容量（逻辑提示，仅提醒管理员，实际MariaDB没有硬限制）"
      echo -e "ℹ️ 请输入要设置提醒容量（单位MB，例如 500）："
      read capacity
      echo -e "${yellow}⚠️ 注意：MariaDB不支持直接硬性限制数据库容量，需靠监控。${reset}"
      echo -e "${green}✔️ 容量提醒设置为 ${capacity} MB，请结合监控系统管理！${reset}"
      draw_footer
      return_menu
      ;;
    0)
      bash /root/VPN/menu/mail.sh
      ;;
    *)
      echo -e "${red}❌ 无效输入，请重新选择！${reset}"
      sleep 1
      ;;
  esac
done
