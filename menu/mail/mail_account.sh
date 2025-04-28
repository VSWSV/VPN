#!/bin/bash

# ==============================================
# 数据库管理脚本 (MySQL/PostgreSQL)
# 版本：v2.1 (样式优化版)
# ==============================================

# ----------------------------
# 颜色定义
# ----------------------------
orange='\033[0;33m'
cyan='\033[0;36m'
red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
reset='\033[0m'

# ----------------------------
# 绘制标题边框
# ----------------------------
draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                                 ${orange}🛢️ 数据库管理系统${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

# ----------------------------
# 绘制底部边框
# ----------------------------
draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# ----------------------------
# 检测当前数据库类型
# ----------------------------
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

# ----------------------------
# 新建数据库（完整功能）
# ----------------------------
create_database() {
    draw_header
    local db_type=$(detect_db)
    
    echo -e "${blue}=== 新建数据库 ===${reset}"
    
    # 输入基础信息
    echo -n "输入数据库名称: "
    read db_name
    echo -n "输入字符集 (MySQL默认: utf8mb4, PostgreSQL默认: UTF8): "
    read charset
    echo -n "输入排序规则 (MySQL默认: utf8mb4_unicode_ci, PostgreSQL默认: en_US.UTF-8): "
    read collation
    echo -n "是否创建关联用户？(y/n): "
    read create_user

    # 创建数据库
    case $db_type in
        mysql)
            charset=${charset:-utf8mb4}
            collation=${collation:-utf8mb4_unicode_ci}
            mysql -u root -p -e "CREATE DATABASE \`$db_name\` CHARACTER SET $charset COLLATE $collation;"
            echo -e "${green}MySQL数据库 '$db_name' 创建成功 (字符集: $charset, 排序规则: $collation)${reset}"
            ;;
        postgres)
            charset=${charset:-UTF8}
            collation=${collation:-en_US.UTF-8}
            sudo -u postgres psql -c "CREATE DATABASE \"$db_name\" ENCODING '$charset' LC_COLLATE '$collation';"
            echo -e "${green}PostgreSQL数据库 '$db_name' 创建成功 (字符集: $charset, 排序规则: $collation)${reset}"
            ;;
    esac

    # 创建用户并授权
    if [ "$create_user" = "y" ]; then
        echo -n "输入用户名: "
        read username
        echo -n "输入密码 (密码会隐藏输入): "
        read -s password
        echo

        case $db_type in
            mysql)
                mysql -u root -p -e "CREATE USER '$username'@'%' IDENTIFIED BY '$password'; GRANT ALL ON \`$db_name\`.* TO '$username'@'%'; FLUSH PRIVILEGES;"
                echo -e "${green}MySQL用户 '$username' 创建并授权访问数据库 '$db_name'${reset}"
                ;;
            postgres)
                sudo -u postgres psql -c "CREATE USER \"$username\" WITH PASSWORD '$password'; GRANT ALL ON DATABASE \"$db_name\" TO \"$username\";"
                echo -e "${green}PostgreSQL用户 '$username' 创建并授权访问数据库 '$db_name'${reset}"
                ;;
        esac
    fi
    draw_footer
    return_to_menu
}

# ----------------------------
# 删除数据库（强制模式）
# ----------------------------
delete_database() {
    draw_header
    local db_type=$(detect_db)
    
    echo -e "${red}=== 删除数据库（危险操作！） ===${reset}"
    
    # 输入要删除的数据库名
    echo -n "输入要删除的数据库名称: "
    read db_name
    
    # 检查数据库是否存在
    case $db_type in
        mysql)
            exists=$(mysql -u root -p -e "SHOW DATABASES LIKE '$db_name';" | grep -c "$db_name")
            ;;
        postgres)
            exists=$(sudo -u postgres psql -l | grep -c "$db_name")
            ;;
    esac
    
    if [ "$exists" -eq 0 ]; then
        echo -e "${red}错误：数据库 '$db_name' 不存在！${reset}"
        draw_footer
        return_to_menu
        return
    fi

    # 二次确认
    echo -e "${red}警告：这将永久删除数据库 '$db_name' 及其所有数据！${reset}"
    echo -n "确认删除？(输入 'DELETE' 继续): "
    read confirm
    
    if [ "$confirm" != "DELETE" ]; then
        echo -e "${orange}操作已取消。${reset}"
        draw_footer
        return_to_menu
        return
    fi

    # 处理活跃连接（仅PostgreSQL需要显式处理）
    if [ "$db_type" = "postgres" ]; then
        echo -e "${orange}终止活跃连接...${reset}"
        sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$db_name';"
    fi

    # 执行删除
    case $db_type in
        mysql)
            mysql -u root -p -e "DROP DATABASE \`$db_name\`;"
            echo -e "${green}MySQL数据库 '$db_name' 已删除！${reset}"
            ;;
        postgres)
            sudo -u postgres psql -c "DROP DATABASE \"$db_name\";"
            echo -e "${green}PostgreSQL数据库 '$db_name' 已删除！${reset}"
            ;;
    esac

    # 可选：级联删除关联用户
    echo -n "是否删除该数据库的专属用户？(y/n): "
    read delete_user
    if [ "$delete_user" = "y" ]; then
        echo -n "输入用户名: "
        read username
        case $db_type in
            mysql)
                mysql -u root -p -e "DROP USER '$username'@'%';"
                echo -e "${green}MySQL用户 '$username' 已删除！${reset}"
                ;;
            postgres)
                sudo -u postgres psql -c "DROP USER \"$username\";"
                echo -e "${green}PostgreSQL用户 '$username' 已删除！${reset}"
                ;;
        esac
    fi
    draw_footer
    return_to_menu
}

# ----------------------------
# 修改密码（Root/普通用户）
# ----------------------------
change_password() {
    draw_header
    local db_type=$(detect_db)
    
    echo -e "${blue}=== 修改密码 ===${reset}"
    echo "1. 修改 root/postgres 密码"
    echo "2. 修改其他用户密码"
    echo -n "请选择 [1-2]: "
    read sub_choice

    case $sub_choice in
        1)
            if [ "$db_type" = "mysql" ]; then
                echo -n "输入新的 root 密码: "
                read -s new_pass
                mysql -u root -p -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$new_pass'; FLUSH PRIVILEGES;"
                echo -e "${green}MySQL root 密码修改成功！${reset}"
            else
                echo -n "输入新的 postgres 密码: "
                read -s new_pass
                sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$new_pass';"
                echo -e "${green}PostgreSQL postgres 密码修改成功！${reset}"
            fi
            ;;
        2)
            echo -n "输入要修改的用户名: "
            read username
            echo -n "输入新密码: "
            read -s new_pass
            
            if [ "$db_type" = "mysql" ]; then
                mysql -u root -p -e "ALTER USER '$username'@'localhost' IDENTIFIED BY '$new_pass'; FLUSH PRIVILEGES;"
                echo -e "${green}MySQL 用户 '$username' 密码修改成功！${reset}"
            else
                sudo -u postgres psql -c "ALTER USER \"$username\" WITH PASSWORD '$new_pass';"
                echo -e "${green}PostgreSQL 用户 '$username' 密码修改成功！${reset}"
            fi
            ;;
        *)
            echo -e "${red}无效选项！${reset}"
            ;;
    esac
    draw_footer
    return_to_menu
}

# ----------------------------
# 列出所有数据库
# ----------------------------
list_databases() {
    draw_header
    local db_type=$(detect_db)

    echo -e "${blue}=== 数据库列表 ===${reset}"
    case $db_type in
        mysql)
            mysql -u root -p -e "SHOW DATABASES;"
            ;;
        postgres)
            sudo -u postgres psql -l
            ;;
    esac
    draw_footer
    return_to_menu
}

# ----------------------------
# 数据库服务管理
# ----------------------------
manage_service() {
    draw_header
    local db_type=$(detect_db)
    
    echo -e "${blue}=== 服务管理 ===${reset}"
    echo "1. 启动服务"
    echo "2. 停止服务"
    echo "3. 重启服务"
    echo "4. 查看状态"
    echo -n "请选择 [1-4]: "
    read service_choice

    case $service_choice in
        1)
            systemctl start $db_type
            ;;
        2)
            systemctl stop $db_type
            ;;
        3)
            systemctl restart $db_type
            ;;
        4)
            systemctl status $db_type
            ;;
        *)
            echo -e "${red}无效选项！${reset}"
            ;;
    esac
    draw_footer
    return_to_menu
}

# ----------------------------
# 返回菜单
# ----------------------------
return_to_menu() {
    read -p "$(echo -e "💬 ${cyan}按回车键返回主菜单...${reset}")" dummy
    clear
}

# ----------------------------
# 主菜单
# ----------------------------
show_menu() {
    clear
    draw_header
    echo -e "${orange}1. 新建数据库${reset}"
    echo -e "${orange}2. 删除数据库${reset}"
    echo -e "${orange}3. 修改密码${reset}"
    echo -e "${orange}4. 列出所有数据库${reset}"
    echo -e "${orange}5. 服务管理${reset}"
    echo -e "${red}0. 退出脚本${reset}"
    echo -e "${cyan}══════════════════════════════════════════════════════════════════════════════${reset}"
    echo -n "请选择操作 [0-5]: "
}

# ----------------------------
# 主程序
# ----------------------------
main() {
    # 检查root权限
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${red}错误: 此脚本需要root权限. 请使用 sudo 运行.${reset}"
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
            5) manage_service ;;
            0) echo -e "${green}已退出脚本。${reset}"; exit 0 ;;
            *) echo -e "${red}错误：无效选项！${reset}" ;;
        esac
    done
}

# 启动脚本
main
