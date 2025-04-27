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
  printf "%-20s %40s\n" "  ${orange}📬 MariaDB数据库管理器${reset}" "$(date +'%Y-%m-%d %H:%M:%S')"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 安全读取输入
safe_input() {
  local prompt=$1
  local max_retry=${2:-3}  # 默认重试3次
  local is_password=${3:-false}
  local value=""
  
  for ((i=1; i<=$max_retry; i++)); do
    if $is_password; then
      read -s -p "$prompt" value
      echo  # password input需要换行
    else
      read -p "$prompt" value
    fi
    
    # 基础输入验证
    if [[ -n "$value" ]]; then
      # 检查数据库名是否合法
      if [[ "$prompt" == *"数据库名"* ]] && ! [[ "$value" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo -e "${red}错误：数据库名只能包含字母、数字和下划线${reset}"
        continue
      fi
      echo "$value"
      return 0
    else
      echo -e "${yellow}输入不能为空，请重新输入 (剩余尝试次数: $((max_retry-i)))${reset}"
    fi
  done
  
  echo -e "${red}错误：输入尝试次数过多${reset}"
  return 1
}

# 更友好的MySQL登录
function mysql_login() {
  local max_retry=3
  for ((i=1; i<=max_retry; i++)); do
    clear
    draw_header
    echo -e "🔐 ${orange}MySQL登录验证${reset}"
    echo -e "${yellow}尝试 $i/$max_retry${reset}"
    mysql -u root -p -e "EXIT" 2>/dev/null
    
    case $? in
      0) return 0 ;;
      1) echo -e "${red}❌ 密码错误${reset}" ;;
      *) echo -e "${red}❌ 连接MySQL服务器失败${reset}" ;;
    esac
    
    if ((i < max_retry)); then
      echo -e "${yellow}3秒后重试...${reset}"
      sleep 3
    fi
  done
  
  echo -e "${red}错误：最大尝试次数已达，请检查MySQL服务是否运行${reset}"
  exit 1
}

# 显示数据库列表（带分页）
function show_databases() {
  clear
  draw_header
  
  # 获取数据库列表
  local dblist=$(mysql -u root -p -e "SHOW DATABASES;" 2>/dev/null | grep -Ev "Database|information_schema|mysql|performance_schema|sys")
  
  # 显示带序号的列表
  echo -e "${green}📦 可用数据库列表:${reset}\n"
  local count=0
  for db in $dblist; do
    ((count++))
    dbpath="/var/lib/mysql/${db}"
    size=$(du -sh "$dbpath" 2>/dev/null | awk '{print $1}')
    echo -e "  ${yellow}${count}.${reset} ${green}${db}${reset} (${blue}${size:-未知}${reset})"
  done
  
  draw_footer
}

# 新建数据库（带完整验证）
function create_database() {
  while true; do
    clear
    draw_header
    echo -e "${green}🆕 创建新数据库${reset}"
    
    # 获取输入
    dbname=$(safe_input "请输入数据库名: " 3)
    [[ $? -ne 0 ]] && return
    
    # 检查是否已存在
    if mysql -u root -p -e "USE \`$dbname\`" 2>/dev/null; then
      echo -e "${red}错误：数据库 $dbname 已存在${reset}"
      return_menu
      continue
    fi
    
    dbuser=$(safe_input "请输入用户名: " 3)
    [[ $? -ne 0 ]] && return
    
    # 检查用户名是否合法
    if [[ "$dbuser" == "root" ]]; then
      echo -e "${red}错误：不能使用root作为普通用户名${reset}"
      return_menu
      continue
    fi
    
    echo -e "请输入密码: "
    dbpass=$(safe_input "" 3 true)
    [[ $? -ne 0 ]] && return
    
    # 确认信息
    echo -e "\n${yellow}请确认以下信息:${reset}"
    echo -e "数据库名: ${green}$dbname${reset}"
    echo -e "用户名: ${green}$dbuser${reset}"
    echo -e "密码: ${green}******${reset}"
    
    if confirm "确认创建吗？"; then
      mysql -u root -p <<EOF
CREATE DATABASE \`${dbname}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}';
GRANT ALL PRIVILEGES ON \`${dbname}\`.* TO '${dbuser}'@'localhost';
FLUSH PRIVILEGES;
EOF
      if [ $? -eq 0 ]; then
        echo -e "${green}✔️ 创建成功！${reset}"
        echo -e "${yellow}📋 连接信息:${reset}"
        echo -e "主机: ${blue}localhost${reset}"
        echo -e "数据库: ${blue}$dbname${reset}"
        echo -e "用户名: ${blue}$dbuser${reset}"
        echo -e "密码: ${blue}******${reset}"
      else
        echo -e "${red}❌ 创建失败！${reset}"
      fi
    else
      echo -e "${yellow}已取消创建操作${reset}"
    fi
    
    return_menu
    break
  done
}

# 确认对话框
confirm() {
  local prompt=$1
  read -p "$prompt [y/N]: " choice
  case "$choice" in
    y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

# 主菜单
function main_menu() {
  while true; do
    show_databases

    echo -e "\n${green}🛠️ 请选择操作:${reset}"
    echo -e "  ${yellow}1${reset}. 创建数据库"
    echo -e "  ${yellow}2${reset}. 删除数据库"
    echo -e "  ${yellow}3${reset}. 密码管理"
    echo -e "  ${yellow}4${reset}. 数据库备份"
    echo -e "  ${yellow}0${reset}. 退出"
    
    local choice
    read -p "请输入选项: " choice
    
    case $choice in
      1) create_database ;;
      2) delete_database ;;
      3) change_password_menu ;;
      4) backup_database ;;
      0) exit 0 ;;
      *) echo -e "${red}无效选项，请重新输入${reset}"; sleep 1 ;;
    esac
  done
}

# 初始化
mysql_login
main_menu
