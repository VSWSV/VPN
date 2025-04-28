#!/bin/bash

orange='\033[0;33m'
cyan='\033[0;36m'
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
reset='\033[0m'

draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                                 ${orange}🛢️ 数据库管理系统${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

safe_yn_input() {
  local prompt="$1"
  local var_name="$2"
  while true; do
    echo -n "$prompt (y/n): "
    read $var_name
    case ${!var_name} in
      [Yy]|[Nn]) break ;;
      *) echo -e "${red}错误：请输入 y 或 n${reset}" ;;
    esac
  done
}

run_mysql() {
  local sql="$1"
  local result
  result=$(mysql -u root -p -e "$sql" 2>&1 | grep -v "Using a password")
  if [[ $result == *"ERROR"* ]]; then
    echo -e "${red}操作失败：${result#*ERROR}${reset}"
    return 1
  fi
  echo "$result"
  return 0
}

run_psql() {
  local sql="$1"
  local result
  result=$(sudo -u postgres psql -c "$sql" 2>&1)
  if [[ $result == *"ERROR"* || $result == *"错误"* ]]; then
    echo -e "${red}操作失败：${result#*ERROR}${reset}"
    return 1
  fi
  echo "$result"
  return 0
}

detect_db() {
    if systemctl is-active --quiet mysql; then
        echo "mysql"
    elif systemctl is-active --quiet postgresql; then
        echo "postgres"
    else
        echo -e "${red}错误：未检测到运行的数据库服务！${reset}"
        exit 1
    fi
}

list_users() {
    draw_header
    local db_type=$(detect_db)
    
    echo -e "${blue}=== 用户列表 ===${reset}"
    local output
    case $db_type in
        mysql)
            output=$(run_mysql "SELECT user,host FROM mysql.user;")
            [[ $? -eq 0 ]] && echo "$output"
            ;;
        postgres)
            output=$(run_psql "\du")
            [[ $? -eq 0 ]] && echo "$output"
            ;;
    esac
    draw_footer
    return_to_menu
}

create_database() {
    draw_header
    local db_type=$(detect_db)
    
    echo -e "${blue}=== 新建数据库 ===${reset}"
    
    while true; do
        echo -n "输入数据库名称: "
        read db_name
        if [ -z "$db_name" ]; then
            echo -e "${red}错误：数据库名不能为空！${reset}"
        else
            break
        fi
    done

    case $db_type in
        mysql)
            if run_mysql "CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" >/dev/null; then
                echo -e "${green}数据库 ${db_name} 创建成功${reset}"
            fi
            ;;
        postgres)
            if run_psql "CREATE DATABASE \"$db_name\" ENCODING 'UTF8' LC_COLLATE 'en_US.UTF-8';" >/dev/null; then
                echo -e "${green}数据库 ${db_name} 创建成功${reset}"
            fi
            ;;
    esac
    draw_footer
    return_to_menu
}

delete_database() {
    draw_header
    local db_type=$(detect_db)
    
    echo -e "${red}=== 删除数据库 ===${reset}"
    
    while true; do
        echo -n "输入要删除的数据库名称: "
        read db_name
        if [ -z "$db_name" ]; then
            echo -e "${red}错误：数据库名不能为空！${reset}"
        else
            break
        fi
    done

    case $db_type in
        mysql)
            if run_mysql "DROP DATABASE \`$db_name\`;" >/dev/null; then
                echo -e "${green}数据库 ${db_name} 删除成功${reset}"
            else
                echo -e "${red}数据库 ${db_name} 不存在或删除失败${reset}"
            fi
            ;;
        postgres)
            run_psql "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$db_name';" >/dev/null 2>&1
            if run_psql "DROP DATABASE \"$db_name\";" >/dev/null; then
                echo -e "${green}数据库 ${db_name} 删除成功${reset}"
            else
                echo -e "${red}数据库 ${db_name} 不存在或删除失败${reset}"
            fi
            ;;
    esac
    draw_footer
    return_to_menu
}

change_password() {
    draw_header
    local db_type=$(detect_db)
    
    echo -e "${blue}=== 修改密码 ===${reset}"
    
    echo -n "输入要修改的用户名: "
    read username
    
    echo -n "输入新密码（输入不可见）: "
    read -s new_pass
    echo

    case $db_type in
        mysql)
            if run_mysql "ALTER USER '$username'@'localhost' IDENTIFIED BY '$new_pass'; FLUSH PRIVILEGES;" >/dev/null; then
                echo -e "${green}用户 ${username} 密码修改成功${reset}"
            else
                echo -e "${red}用户 ${username} 密码修改失败${reset}"
            fi
            ;;
        postgres)
            if run_psql "ALTER USER \"$username\" WITH PASSWORD '$new_pass';" >/dev/null; then
                echo -e "${green}用户 ${username} 密码修改成功${reset}"
            else
                echo -e "${red}用户 ${username} 密码修改失败${reset}"
            fi
            ;;
    esac
    draw_footer
    return_to_menu
}

list_databases() {
    draw_header
    local db_type=$(detect_db)

    echo -e "${blue}=== 数据库列表 ===${reset}"
    local output
    case $db_type in
        mysql)
            output=$(run_mysql "SHOW DATABASES;")
            [[ $? -eq 0 ]] && echo "$output"
            ;;
        postgres)
            output=$(run_psql "\l")
            [[ $? -eq 0 ]] && echo "$output"
            ;;
    esac
    draw_footer
    return_to_menu
}

return_to_menu() {
    read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

show_menu() {
    clear
    draw_header
    echo -e "${orange}1. 新建数据库${reset}"
    echo -e "${orange}2. 删除数据库${reset}"
    echo -e "${orange}3. 修改密码${reset}"
    echo -e "${orange}4. 列出所有数据库${reset}"
    echo -e "${orange}5. 查看所有用户${reset}"
    echo -e "${red}0. 返回上级菜单${reset}"
    echo -e "${cyan}══════════════════════════════════════════════════════════════════════════════${reset}"
    echo -n "请选择操作 [0-5]: "
}

main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${red}错误: 此脚本需要root权限${reset}"
        exit 1
    fi

    while true; do
        show_menu
        read choice

        case $choice in
            1) create_database ;;
            2) delete_database ;;
            3) change_password ;;
            4) list_databases ;;
            5) list_users ;;
            0) bash /root/VPN/menu/mail.sh; exit ;;
            *) echo -e "${red}错误：无效选项！${reset}" ;;
        esac
    done
}

main
