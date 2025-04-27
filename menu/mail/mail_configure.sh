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

# 返回小菜单
return_menu() {
  read -p "$(echo -e "💬 ${cyan}按回车键返回数据库管理菜单...${reset}")" dummy
}

# 登录数据库（原生Enter password版）
function mysql_login() {
  while true; do
    clear
    mysql -u root -p -e "EXIT" 2>/dev/null
    if [ $? -eq 0 ]; then
      break
    else
      echo -e "${red}❌ 密码错误，请重新输入！${reset}"
      sleep 1
    fi
  done
}

# 展示数据库和容量
function show_databases() {
  clear
  draw_header
  echo -e "ℹ️ 当前用户数据库及容量：\n"

  dblist=$(mysql -u root -p -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "Database|information_schema|mysql|performance_schema|sys")

  for db in $dblist; do
    dbpath="/var/lib/mysql/${db}"
    if [ -d "$dbpath" ]; then
      size=$(du -sm "$dbpath" | awk '{print $1}')
      echo -e "  📋 ${green}${db}${reset}    ${yellow}${size} MB${reset}"
    fi
  done

  draw_footer
}

# 修改密码二级菜单
function change_password_menu() {
  while true; do
    clear
    draw_header
    echo -e "  ${yellow}①${reset} ${green}修改普通密码${reset}          ${yellow}②${reset} ${green}修改管理密码${reset}"
    echo -e "  ${yellow}⓪${reset} ${red}返回上一级菜单${reset}"
    draw_footer

    read -p "请输入选项编号：" opt2
    case $opt2 in
      1)
        clear
        draw_header
        echo -e "ℹ️ 当前数据库用户列表（列出数据库名）：\n"
        dblist=$(mysql -u root -p -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "Database|information_schema|mysql|performance_schema|sys")
        for db in $dblist; do
          echo -e "  📋 ${green}${db}${reset}"
        done
        draw_footer
        echo -e "ℹ️ 请输入关联数据库名："
        read dbname_user
        echo -e "ℹ️ 请输入要修改密码的用户名："
        read user_to_change
        echo -e "ℹ️ 请输入新密码："
        read -s newpass
        mysql -u root -p -e "ALTER USER '${user_to_change}'@'localhost' IDENTIFIED BY '${newpass}'; FLUSH PRIVILEGES;"
        if [ $? -eq 0 ]; then
          echo -e "${green}✔️ 用户 ${user_to_change} 密码修改成功！${reset}"
        else
          echo -e "${red}❌ 修改失败！请检查用户名是否存在！${reset}"
        fi
        return_menu
        break
        ;;
      2)
        clear
        draw_header
        echo -e "ℹ️ 正在修改MySQL root账户密码..."
        echo -e "ℹ️ 请输入新root密码："
        read -s newrootpass
        echo -e "ℹ️ 请再次确认新root密码："
        read -s newrootpass2
        if [ "$newrootpass" != "$newrootpass2" ]; then
          echo -e "${red}❌ 两次密码输入不一致！${reset}"
          return_menu
          break
        fi
        mysql -u root -p -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${newrootpass}'; FLUSH PRIVILEGES;"
        if [ $? -eq 0 ]; then
          echo -e "${green}✔️ root密码修改成功！${reset}"
        else
          echo -e "${red}❌ 修改失败！${reset}"
        fi
        return_menu
        break
        ;;
      0)
        break
        ;;
      *)
        echo -e "${red}❌ 无效输入，请重新选择！${reset}"
        sleep 1
        ;;
    esac
  done
}

# 主菜单
function main_menu() {
  while true; do
    show_databases

    echo -e "  ${yellow}①${reset} ${green}新建数据库${reset}           ${yellow}②${reset} ${green}删除数据库${reset}"
    echo -e "  ${yellow}③${reset} ${green}修改密码${reset}              ${yellow}⓪${reset} ${red}返回上一级菜单${reset}"
    draw_footer

    read -p "请输入选项编号：" opt
    case $opt in
      1)
        clear
        draw_header
        echo -e "ℹ️ 请输入要新建的数据库名称："
        read dbname
        echo -e "ℹ️ 请输入新建的数据库用户名（不要用root）："
        read dbuser
        if [[ "$dbuser" == "root" ]]; then
          echo -e "${red}❌ 不允许用root作为普通账户！${reset}"
          return_menu
          continue
        fi
        echo -e "ℹ️ 请输入数据库用户密码："
        read -s dbpass
        draw_footer

        mysql -u root -p -e "
CREATE DATABASE IF NOT EXISTS \`${dbname}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}';
GRANT ALL PRIVILEGES ON \`${dbname}\`.* TO '${dbuser}'@'localhost';
FLUSH PRIVILEGES;
"
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
        echo -e "ℹ️ 当前用户数据库列表："
        dblist=$(mysql -u root -p -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "Database|information_schema|mysql|performance_schema|sys")
        for db in $dblist; do
          echo -e "  📋 ${green}${db}${reset}"
        done
        draw_footer
        echo -e "ℹ️ 请输入要删除的数据库名称："
        read dbname_del

        if echo "$dblist" | grep -qw "$dbname_del"; then
          echo -e "⚠️ 确认要删除数据库 ${dbname_del} 吗？此操作不可逆！(y/n)"
          read confirm
          if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            mysql -u root -p -e "DROP DATABASE \`${dbname_del}\`;"
            if [ $? -eq 0 ]; then
              echo -e "${green}✔️ 数据库 ${dbname_del} 删除成功！${reset}"
            else
              echo -e "${red}❌ 删除失败！${reset}"
            fi
          else
            echo -e "${red}❌ 已取消删除操作。${reset}"
          fi
        else
          echo -e "${red}❌ 数据库 ${dbname_del} 不存在！${reset}"
        fi
        return_menu
        ;;
      3)
        change_password_menu
        ;;
      0)
        bash /root/VPN/menu/mail.sh
        exit 0
        ;;
      *)
        echo -e "${red}❌ 无效输入，请重新选择！${reset}"
        sleep 1
        ;;
    esac
  done
}

# 主程序开始
mysql_login
main_menu
