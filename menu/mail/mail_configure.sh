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
  echo -e "                               ${orange}📬 邮局数据库管理器${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

return_menu() {
  read -p "$(echo -e "💬 ${cyan}按回车键返回主菜单...${reset}")" dummy
  bash /root/VPN/menu/mail.sh
}

# 检查MySQL是否安装
if ! command -v mysql >/dev/null 2>&1; then
  echo -e "${red}❌ 未检测到MySQL，无法继续！${reset}"
  exit 1
fi

# 检查MySQL服务是否运行
if ! systemctl is-active --quiet mysql; then
  echo -e "${red}❌ MySQL服务未运行，请先启动MySQL！${reset}"
  exit 1
fi

# 开始脚本
clear
draw_header
echo -e "${cyan}▶ 现在需要输入 MySQL root 账户密码（由MySQL原生弹出 Enter password: ）${reset}"
draw_footer

# 检查密码是否正确
if ! mysql -u root -p -e "SELECT 1;" 2>/dev/null; then
  echo -e "${red}❌ 无法连接MySQL，请检查密码！${reset}"
  exit 1
fi

# 输入数据库信息
draw_header
echo -e "${cyan}▶ 请输入要创建的数据库名称（如 maildb）：${reset}"
read dbname
if [[ "$dbname" =~ [^a-zA-Z0-9_] ]]; then
  echo -e "${red}❌ 数据库名只能包含字母、数字、下划线！${reset}"
  exit 1
fi

echo -e "${cyan}▶ 请输入新建的数据库用户名（如 mailuser，不允许root）：${reset}"
read dbuser
if [[ "$dbuser" == "root" || "$dbuser" =~ [^a-zA-Z0-9_] ]]; then
  echo -e "${red}❌ 用户名不能是root，且只能包含字母数字下划线！${reset}"
  exit 1
fi

echo -e "${cyan}▶ 请输入数据库用户密码（复杂些）：${reset}"
read -s dbpass
echo -e "${cyan}▶ 请再次确认数据库用户密码：${reset}"
read -s dbpass_confirm
if [ "$dbpass" != "$dbpass_confirm" ]; then
  echo -e "${red}❌ 两次输入的密码不一致！${reset}"
  exit 1
fi
draw_footer

# 检查是否存在
if mysql -u root -p -e "SHOW DATABASES LIKE '${dbname}';" | grep "${dbname}" >/dev/null; then
  echo -e "${yellow}⚠️ 数据库${dbname}已存在，是否覆盖？(y/n)${reset}"
  read overwrite_db
  if [[ "$overwrite_db" != "y" ]]; then
    echo -e "${red}❌ 已取消操作。${reset}"
    exit 1
  fi
fi

if mysql -u root -p -e "SELECT User FROM mysql.user WHERE User='${dbuser}';" | grep "${dbuser}" >/dev/null; then
  echo -e "${yellow}⚠️ 用户${dbuser}已存在，是否覆盖？(y/n)${reset}"
  read overwrite_user
  if [[ "$overwrite_user" != "y" ]]; then
    echo -e "${red}❌ 已取消操作。${reset}"
    exit 1
  fi
fi

# 正式创建数据库和用户
draw_header
echo -e "${cyan}▶ 正在创建数据库和用户...${reset}"

mysql -u root -p <<EOF
DROP DATABASE IF EXISTS ${dbname};
CREATE DATABASE ${dbname} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
DROP USER IF EXISTS '${dbuser}'@'localhost';
CREATE USER '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}';
GRANT ALL PRIVILEGES ON ${dbname}.* TO '${dbuser}'@'localhost';
FLUSH PRIVILEGES;
EOF

if [ $? -ne 0 ]; then
  echo -e "${red}❌ 创建数据库或用户失败！${reset}"
  exit 1
fi

echo -e "${green}✅ 数据库 ${dbname} 和用户 ${dbuser} 创建成功！${reset}"
draw_footer

# 导入Roundcube表结构
draw_header
echo -e "${cyan}▶ 正在导入Roundcube表结构...${reset}"

if [ ! -f /root/VPN/MAIL/roundcube/SQL/mysql.initial.sql ]; then
  echo -e "${red}❌ Roundcube初始化SQL文件不存在！${reset}"
  exit 1
fi

mysql -u "${dbuser}" -p "${dbname}" < /root/VPN/MAIL/roundcube/SQL/mysql.initial.sql

if [ $? -ne 0 ]; then
  echo -e "${red}❌ 表结构导入失败！${reset}"
  exit 1
fi

echo -e "${green}✅ 表结构导入成功！${reset}"
mysql -u "${dbuser}" -p -e "USE ${dbname}; SHOW TABLES;"

draw_footer

# 保存数据库连接信息
mkdir -p /root/VPN/MAIL/
cat >/root/VPN/MAIL/db_info.txt <<EOL
数据库名称: ${dbname}
数据库用户名: ${dbuser}
数据库密码: ${dbpass}
连接命令: mysql -u ${dbuser} -p ${dbname}
EOL

echo -e "${green}✅ 配置信息已保存到 /root/VPN/MAIL/db_info.txt${reset}"

# 返回菜单
return_menu
