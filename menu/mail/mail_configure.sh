#!/bin/bash

# 颜色定义
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
cyan="\033[1;36m"
orange="\033[38;5;214m"
reset="\033[0m"

# 界面绘制函数
draw_header() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  printf "%-40s %40s\n" "  ${orange}📊 MariaDB专业管理工具${reset}" "$(date +'%Y-%m-%d %H:%M:%S')"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 安全输入函数
safe_input() {
  local prompt=$1
  local pattern=$2
  local max_retry=${3:-3}
  local is_password=${4:-false}
  
  for ((i=1; i<=max_retry; i++)); do
    if $is_password; then
      read -s -p "$prompt" value
      echo
    else
      read -p "$prompt" value
    fi
    
    if [[ -z "$value" ]]; then
      echo -e "${red}错误：输入不能为空${reset}"
      continue
    fi
    
    if [[ -n "$pattern" ]] && ! [[ "$value" =~ $pattern ]]; then
      echo -e "${red}错误：输入格式不符合要求${reset}"
      continue
    fi
    
    echo "$value"
    return 0
  done
  
  echo -e "${red}错误：超过最大尝试次数${reset}"
  return 1
}

# 数据库创建模块 (完整实现)
create_database() {
  while true; do
    draw_header
    echo -e "${green}🆕 创建新数据库系统${reset}"
    echo -e "${cyan}──────────────────────────────────────${reset}"
    
    # 数据库信息
    echo -e "${yellow}步骤 1/3：数据库基本信息${reset}"
    local dbname=$(safe_input "▶ 请输入数据库名(只允许字母数字下划线): " "^[a-zA-Z0-9_]+$" 3)
    [[ $? -ne 0 ]] && return
    
    # 检查是否已存在
    if mysql -u root -p -e "USE \`$dbname\`" 2>/dev/null; then
      echo -e "${red}错误：数据库已存在${reset}"
      return_menu
      continue
    fi
    
    # 用户信息
    echo -e "\n${yellow}步骤 2/3：数据库用户配置${reset}"
    local dbuser=$(safe_input "▶ 请输入用户名(不要使用root): " "^[a-zA-Z0-9_]+$" 3)
    [[ $? -ne 0 ]] && return
    
    if [[ "$dbuser" == "root" ]]; then
      echo -e "${red}安全拒绝：禁止使用root作为应用账号${reset}"
      return_menu
      continue
    fi
    
    echo -e "▶ 请输入密码: "
    local dbpass=$(safe_input "" "" 3 true)
    [[ $? -ne 0 ]] && return
    
    # 权限配置
    echo -e "\n${yellow}步骤 3/3：权限配置${reset}"
    echo -e "${blue}可选权限级别：${reset}"
    echo -e "1. 读写权限 (ALL PRIVILEGES)"
    echo -e "2. 只读权限 (SELECT)"
    echo -e "3. 自定义权限"
    
    local priv_choice
    local privileges="ALL PRIVILEGES"
    read -p "▶ 请选择权限级别(默认1): " priv_choice
    case $priv_choice in
      2) privileges="SELECT" ;;
      3) 
        read -p "▶ 请输入自定义权限(用逗号分隔): " custom_priv
        privileges="$custom_priv"
        ;;
    esac
    
    # 确认信息
    draw_header
    echo -e "${green}✅ 创建配置确认${reset}"
    echo -e "${cyan}──────────────────────────────────────${reset}"
    echo -e "${blue}数据库名：${reset} ${green}$dbname${reset}"
    echo -e "${blue}用户名：${reset} ${green}$dbuser${reset}"
    echo -e "${blue}权限级别：${reset} ${green}$privileges${reset}"
    echo -e "${cyan}──────────────────────────────────────${reset}"
    
    if confirm "确认创建？(y/N)"; then
      echo -e "${yellow}正在创建数据库系统...${reset}"
      
      mysql -u root -p <<EOF
CREATE DATABASE \`${dbname}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}';
GRANT ${privileges} ON \`${dbname}\`.* TO '${dbuser}'@'localhost';
FLUSH PRIVILEGES;
EOF
      
      if [ $? -eq 0 ]; then
        echo -e "${green}✔️ 创建成功！${reset}"
        echo -e "${yellow}连接信息已生成：${reset}"
        echo -e "${cyan}──────────────────────────────────────${reset}"
        echo -e "${blue}主机：${reset} localhost"
        echo -e "${blue}端口：${reset} 3306"
        echo -e "${blue}数据库：${reset} $dbname"
        echo -e "${blue}用户名：${reset} $dbuser"
        echo -e "${blue}密码：${reset} ${red}保密${reset}"
        echo -e "${cyan}──────────────────────────────────────${reset}"
      else
        echo -e "${red}❌ 创建过程中出现错误${reset}"
      fi
    else
      echo -e "${yellow}操作已取消${reset}"
    fi
    
    return_menu
    break
  done
}

# 数据库删除模块 (完整实现)
delete_database() {
  while true; do
    draw_header
    echo -e "${red}🗑️ 数据库删除系统${reset}"
    echo -e "${cyan}──────────────────────────────────────${reset}"
    
    # 获取数据库列表
    local databases=$(mysql -u root -p -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "Database|information_schema|mysql|performance_schema|sys")
    local db_array=()
    local i=1
    
    echo -e "${yellow}可删除的数据库：${reset}"
    for db in $databases; do
      db_array+=("$db")
      local user_count=$(mysql -u root -p -e "SELECT COUNT(*) FROM mysql.db WHERE Db = '$db'" 2>/dev/null | tail -1)
      echo -e "${blue}$i.${reset} ${green}$db${reset} (关联用户: ${yellow}$user_count${reset}个)"
      ((i++))
    done
    
    echo -e "\n${yellow}0. 返回主菜单${reset}"
    draw_footer
    
    local choice
    read -p "▶ 请选择要删除的数据库编号: " choice
    
    # 验证输入
    if [[ "$choice" == "0" ]]; then
      return
    elif ! [[ "$choice" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#db_array[@]})); then
      echo -e "${red}无效选择！${reset}"
      sleep 1
      continue
    fi
    
    local db_to_delete=${db_array[$((choice-1))]}
    
    # 获取关联用户详情
    draw_header
    echo -e "${red}⚠️ 数据库删除确认：$db_to_delete${reset}"
    echo -e "${cyan}──────────────────────────────────────${reset}"
    echo -e "${yellow}关联用户列表：${reset}"
    mysql -u root -p -e "SELECT User FROM mysql.db WHERE Db = '$db_to_delete'" 2>/dev/null
    
    echo -e "\n${red}警告：这将永久删除数据库及其所有数据！${reset}"
    
    if confirm "确定要删除数据库 '$db_to_delete' 吗？(y/N)"; then
      # 先删除关联权限
      mysql -u root -p -e "REVOKE ALL PRIVILEGES ON \`${db_to_delete}\`.* FROM '*'@'%'; DROP DATABASE \`${db_to_delete}\`;" 2>/dev/null
      
      # 检查是否删除成功
      if ! mysql -u root -p -e "USE \`$db_to_delete\`" 2>/dev/null; then
        echo -e "${green}✔️ 数据库 '$db_to_delete' 已成功删除${reset}"
        
        # 询问是否删除关联用户
        local users=$(mysql -u root -p -e "SELECT User FROM mysql.db WHERE Db = '$db_to_delete'" 2>/dev/null | tail -n +2)
        if [[ -n "$users" ]]; then
          if confirm "是否一并删除关联用户？(y/N)"; then
            for user in $users; do
              mysql -u root -p -e "DROP USER '$user'@'localhost';" 2>/dev/null
              echo -e "${yellow}✔️ 已删除用户: $user${reset}"
            done
          fi
        fi
      else
        echo -e "${red}❌ 删除失败！${reset}"
      fi
    else
      echo -e "${yellow}操作已取消${reset}"
    fi
    
    return_menu
    break
  done
}

# 密码管理模块 (完整实现)
password_management() {
  while true; do
    draw_header
    echo -e "${green}🔐 密码管理系统${reset}"
    echo -e "${cyan}──────────────────────────────────────${reset}"
    echo -e "${yellow}1. 修改管理员(root)密码${reset}"
    echo -e "${yellow}2. 修改普通用户密码${reset}"
    echo -e "${yellow}0. 返回主菜单${reset}"
    draw_footer
    
    local choice
    read -p "▶ 请选择操作: " choice
    
    case $choice in
      1) change_root_password ;;
      2) change_user_password ;;
      0) return ;;
      *) 
        echo -e "${red}无效选择！${reset}"
        sleep 1
        ;;
    esac
  done
}

# 修改root密码
change_root_password() {
  draw_header
  echo -e "${orange}🔑 修改管理员密码${reset}"
  echo -e "${cyan}──────────────────────────────────────${reset}"
  
  echo -e "▶ 请输入当前root密码: "
  local current_pass=$(safe_input "" "" 3 true)
  [[ $? -ne 0 ]] && return
  
  # 验证当前密码
  if ! mysql -u root -p"$current_pass" -e "EXIT" 2>/dev/null; then
    echo -e "${red}错误：当前密码不正确${reset}"
    return_menu
    return
  fi
  
  echo -e "▶ 请输入新密码: "
  local new_pass=$(safe_input "" "" 3 true)
  [[ $? -ne 0 ]] && return
  
  echo -e "▶ 请再次输入新密码: "
  local new_pass2=$(safe_input "" "" 3 true)
  [[ $? -ne 0 ]] && return
  
  if [[ "$new_pass" != "$new_pass2" ]]; then
    echo -e "${red}错误：两次输入的密码不匹配${reset}"
    return_menu
    return
  fi
  
  mysql -u root -p"$current_pass" -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$new_pass'; FLUSH PRIVILEGES;" 2>/dev/null
  
  if [ $? -eq 0 ]; then
    echo -e "${green}✔️ root密码修改成功！${reset}"
    echo -e "${yellow}请使用新密码登录系统${reset}"
  else
    echo -e "${red}❌ 密码修改失败${reset}"
  fi
  
  return_menu
}

# 修改普通用户密码
change_user_password() {
  draw_header
  echo -e "${orange}👤 修改普通用户密码${reset}"
  echo -e "${cyan}──────────────────────────────────────${reset}"
  
  # 获取用户列表
  echo -e "${yellow}正在获取用户列表...${reset}"
  local users=$(mysql -u root -p -e "SELECT User FROM mysql.user WHERE User NOT LIKE 'root%' AND User NOT LIKE 'mysql%';" 2>/dev/null | tail -n +2)
  
  if [[ -z "$users" ]]; then
    echo -e "${red}没有找到普通用户${reset}"
    return_menu
    return
  fi
  
  echo -e "${green}可操作的用户列表：${reset}"
  local i=1
  local user_array=()
  for user in $users; do
    user_array+=("$user")
    echo -e "${blue}$i.${reset} $user"
    ((i++))
  done
  
  echo -e "\n${yellow}0. 返回${reset}"
  draw_footer
  
  local choice
  read -p "▶ 请选择用户编号: " choice
  
  # 验证输入
  if [[ "$choice" == "0" ]]; then
    return
  elif ! [[ "$choice" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#user_array[@]})); then
    echo -e "${red}无效选择！${reset}"
    sleep 1
    change_user_password
    return
  fi
  
  local selected_user=${user_array[$((choice-1))]}
  
  # 显示用户权限
  draw_header
  echo -e "${orange}修改用户密码：${green}$selected_user${reset}"
  echo -e "${cyan}──────────────────────────────────────${reset}"
  echo -e "${yellow}当前权限：${reset}"
  mysql -u root -p -e "SHOW GRANTS FOR '$selected_user'@'localhost';" 2>/dev/null | sed 's/$/;/'
  
  echo -e "\n▶ 请输入新密码: "
  local new_pass=$(safe_input "" "" 3 true)
  [[ $? -ne 0 ]] && return
  
  echo -e "▶ 请再次输入新密码: "
  local new_pass2=$(safe_input "" "" 3 true)
  [[ $? -ne 0 ]] && return
  
  if [[ "$new_pass" != "$new_pass2" ]]; then
    echo -e "${red}错误：两次输入的密码不匹配${reset}"
    return_menu
    return
  fi
  
  mysql -u root -p -e "ALTER USER '$selected_user'@'localhost' IDENTIFIED BY '$new_pass'; FLUSH PRIVILEGES;" 2>/dev/null
  
  if [ $? -eq 0 ]; then
    echo -e "${green}✔️ 用户 '$selected_user' 密码修改成功！${reset}"
  else
    echo -e "${red}❌ 密码修改失败${reset}"
  fi
  
  return_menu
}

# 确认对话框
confirm() {
  local prompt=$1
  read -p "$prompt " choice
  case "$choice" in
    [yY][eE][sS]|[yY]) return 0 ;;
    *) return 1 ;;
  esac
}

# 返回菜单
return_menu() {
  read -p "$(echo -e "${cyan}按回车键返回...${reset}")" dummy
}

# 主菜单
main_menu() {
  while true; do
    draw_header
    echo -e "${green}🏠 主菜单${reset}"
    echo -e "${cyan}──────────────────────────────────────${reset}"
    
    # 显示数据库状态
    echo -e "${yellow}📊 数据库状态：${reset}"
    mysql -u root -p -e "SHOW STATUS LIKE 'Uptime'; 
                         SHOW STATUS LIKE 'Threads_connected';" 2>/dev/null | awk '{printf "%-25s %-15s\n", $1,$2}'
    
    # 显示数据库列表
    echo -e "\n${yellow}📦 数据库列表：${reset}"
    mysql -u root -p -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "Database|information_schema|performance_schema" | while read db; do
      size=$(mysql -u root -p -e "SELECT SUM(data_length+index_length)/1024/1024 AS 'Size (MB)' FROM information_schema.TABLES WHERE table_schema='$db'" 2>/dev/null | tail -1)
      echo -e "${blue}▪${reset} ${green}$db${reset} (${yellow}${size:-0} MB${reset})"
    done
    
    echo -e "${cyan}──────────────────────────────────────${reset}"
    echo -e "${yellow}1. 创建数据库系统${reset}"
    echo -e "${yellow}2. 删除数据库${reset}"
    echo -e "${yellow}3. 密码管理系统${reset}"
    echo -e "${yellow}0. 退出${reset}"
    draw_footer
    
    local choice
    read -p "▶ 请选择操作: " choice
    
    case $choice in
      1) create_database ;;
      2) delete_database ;;
      3) password_management ;;
      0) 
        echo -e "${green}感谢使用！${reset}"
        exit 0
        ;;
      *) 
        echo -e "${red}无效选项！${reset}"
        sleep 1
        ;;
    esac
  done
}

# 初始化
mysql_login
main_menu
