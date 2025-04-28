#!/bin/bash

blue='\033[1;34m'
cyan="\033[1;36m"
green="\033[1;32m"
red="\033[1;31m"
orange="\033[38;5;214m"
reset="\033[0m"

# 绘制头部
draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                                 ${orange}🛢️ 数据库管理系统${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

# 绘制底部
draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 运行 MySQL 命令
run_mysql() {
  local sql="$1"
  local result
  result=$(mysql -u root -p -e "$sql" 2>&1 | grep -v "Using a password")
  if [[ $result == *"ERROR"* ]]; then
    echo -e "${red}操作失败：${result}${reset}"
    return 1
  fi
  echo "$result"
  return 0
}

# 运行 PostgreSQL 命令
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

# 检测正在运行的数据库
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

# 列出数据库用户
list_users() {
    local db_type=$(detect_db)
    
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "                                   ${orange}👥 查看用户${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

    case $db_type in
        mysql)
            # 使用 MySQL 查询数据库用户
            mysql -u root -p -e "SELECT User, Host FROM mysql.user;"
            ;;
        postgres)
            # 使用 PostgreSQL 查询数据库用户
            psql -U postgres -c "\du"
            ;;
    esac

    draw_footer
    return_to_menu
}


list_databases() {
    local db_type=$(detect_db)

    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "                                   ${orange}📚 查看数据库${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

    case $db_type in
        mysql)
            # 直接运行 MySQL 查询，输出原生格式的数据库列表
            mysql -u root -p -e "SHOW DATABASES;"
            ;;
        postgres)
            # 直接运行 PostgreSQL 查询，输出原生格式的数据库列表
            psql -U postgres -c "\l"
            ;;
    esac

    draw_footer
    return_to_menu
}


# 创建新数据库并自动创建用户
create_database() {
    local db_type=$(detect_db)
    local success=false
    
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "                                   ${orange}✨ 新建数据库${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    
    while true; do
        echo -n "输入数据库名称: "
        read db_name
        # 检查是否为空或仅包含空格
        if [[ -z "${db_name// }" ]]; then
            echo -e "${red}错误：数据库名不能为空或仅包含空格！${reset}"
        # 检查是否包含空格
        elif [[ "$db_name" =~ [[:space:]] ]]; then
            echo -e "${red}错误：数据库名不能包含空格！${reset}"
        else
            break
        fi
    done

    case $db_type in
        mysql)
            if run_mysql "CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" >/dev/null; then
                echo -e "${green}数据库 ${db_name} 创建成功${reset}"
                success=true
            else
                echo -e "${red}数据库 ${db_name} 创建失败${reset}"
                draw_footer
                return_to_menu
                return
            fi
            ;;
        postgres)
            if run_psql "CREATE DATABASE \"$db_name\" ENCODING 'UTF8' LC_COLLATE 'en_US.UTF-8';" >/dev/null; then
                echo -e "${green}数据库 ${db_name} 创建成功${reset}"
                success=true
            else
                echo -e "${red}数据库 ${db_name} 创建失败${reset}"
                draw_footer
                return_to_menu
                return
            fi
            ;;
    esac

    # 自动创建与数据库关联的用户
    while true; do
        echo -n "输入用户名: "
        read username
        if [[ -z "${username// }" ]]; then
            echo -e "${red}错误：用户名不能为空或仅包含空格！${reset}"
        elif [[ "$username" =~ [[:space:]] ]]; then
            echo -e "${red}错误：用户名不能包含空格！${reset}"
        else
            break
        fi
    done

    while true; do
        echo -n "输入密码（输入不可见）: "
        read -s password
        echo
        if [[ -z "${password// }" ]]; then
            echo -e "${red}错误：密码不能为空或仅包含空格！${reset}"
        elif [[ "$password" =~ [[:space:]] ]]; then
            echo -e "${red}错误：密码不能包含空格！${reset}"
        else
            break
        fi
    done

    case $db_type in
        mysql)
            if run_mysql "CREATE USER '$username'@'%' IDENTIFIED BY '$password'; GRANT ALL ON \`$db_name\`.* TO '$username'@'%'; FLUSH PRIVILEGES;" >/dev/null; then
                echo -e "${green}用户 ${username} 创建并授权成功${reset}"
            else
                echo -e "${red}用户创建失败${reset}"
            fi
            ;;
        postgres)
            if run_psql "CREATE USER \"$username\" WITH PASSWORD '$password'; GRANT ALL ON DATABASE \"$db_name\" TO \"$username\";" >/dev/null; then
                echo -e "${green}用户 ${username} 创建并授权成功${reset}"
            else
                echo -e "${red}用户创建失败${reset}"
            fi
            ;;
    esac

    draw_footer
    return_to_menu
}

# 删除数据库及其关联用户
delete_database() {

    local db_type=$(detect_db)
    
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                                   ${orange}❌ 删除数据库${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    
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
            if run_mysql "DROP DATABASE \$db_name\;" >/dev/null; then
                echo -e "${green}数据库 ${db_name} 删除成功${reset}"
                # 删除关联用户
                if run_mysql "DROP USER '$db_name'@'%';" >/dev/null; then
                    echo -e "${green}关联用户 ${db_name} 删除成功${reset}"
                else
                    echo -e "${red}关联用户删除失败${reset}"
                fi
            else
                echo -e "${red}数据库 ${db_name} 不存在或删除失败${reset}"
            fi
            ;;
        postgres)
            run_psql "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$db_name';" >/dev/null 2>&1
            if run_psql "DROP DATABASE \"$db_name\";" >/dev/null; then
                echo -e "${green}数据库 ${db_name} 删除成功${reset}"
                # 删除关联用户
                if run_psql "DROP USER \"$db_name\";" >/dev/null; then
                    echo -e "${green}关联用户 ${db_name} 删除成功${reset}"
                else
                    echo -e "${red}关联用户删除失败${reset}"
                fi
            else
                echo -e "${red}数据库 ${db_name} 不存在或删除失败${reset}"
            fi
            ;;
    esac
    draw_footer
    return_to_menu
}

# 修改用户密码
change_password() {

    local db_type=$(detect_db)
    
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                                   ${orange}🔑 修改密码${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    
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

# 返回主菜单
return_to_menu() {
    read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

# 显示菜单
show_menu() {
    clear
    draw_header
    echo -e "${green}  1. 新建数据库${reset}                    ${green}2. 删除数据库${reset}                    ${green}4. 查看数据库${reset}"
    echo -e "${green}  3. 修改密码${reset}                      ${green}5. 查看用户${reset}                      ${red}0. 返回${reset}"
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
    echo -n "请选择操作 : "
}


# 主函数
main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${red}错误: 此脚本需要 root 权限运行，请使用 sudo 或切换到 root 用户！${reset}"
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

# 启动主函数
main
