#!/bin/bash

clear

cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
reset="\033[0m"

success_all=0
fail_all=0

function draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                               ${orange}📦 邮局系统卸载${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

function uninstall_package() {
  local pkg=$1
  echo -e "\n🔍 ${yellow}正在卸载软件包: ${pkg}${reset}"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt purge -y "$pkg"
    if [ $? -eq 0 ]; then
      echo -e "${green}✓ 已成功卸载 $pkg${reset}"
      success_all=$((success_all+1))
    else
      echo -e "${red}✗ 卸载失败: $pkg${reset}"
      fail_all=$((fail_all+1))
    fi
  else
    echo -e "${yellow}⚠ 软件包 $pkg 不存在，跳过${reset}"
  fi
}

function remove_path() {
  local path=$1
  echo -e "\n🔍 ${yellow}正在删除路径: ${path}${reset}"
  if [ -e "$path" ]; then
    rm -rf "$path"
    if [ ! -e "$path" ]; then
      echo -e "${green}✓ 成功删除 $path${reset}"
      success_all=$((success_all+1))
    else
      echo -e "${red}✗ 删除失败 $path${reset}"
      fail_all=$((fail_all+1))
    fi
  else
    echo -e "${yellow}⚠ 路径不存在，跳过：$path${reset}"
  fi
}

function remove_users() {
  echo -e "\n🔍 ${yellow}尝试删除系统用户与组 vmail / opendkim${reset}"
  deluser --remove-home vmail >/dev/null 2>&1 && echo -e "${green}✓ 已删除用户 vmail${reset}" || echo -e "${yellow}⚠ 用户 vmail 不存在${reset}"
  delgroup vmail >/dev/null 2>&1 || echo -e "${yellow}⚠ 组 vmail 不存在${reset}"
  deluser opendkim >/dev/null 2>&1 && echo -e "${green}✓ 已删除用户 opendkim${reset}" || echo -e "${yellow}⚠ 用户 opendkim 不存在${reset}"
  delgroup opendkim >/dev/null 2>&1 || echo -e "${yellow}⚠ 组 opendkim 不存在${reset}"
}

echo -e "${yellow}⚡ 卸载操作需要输入密码确认${reset}"
read -p "请输入密码以继续（默认密码: 88）: " user_pass

if [ "$user_pass" != "88" ]; then
  echo -e "${red}❌ 密码错误，卸载已取消！${reset}"
  sleep 0.5
  bash /root/VPN/menu/mail.sh
  exit 1
else
  echo -e "${green}✅ 密码正确，开始卸载！${reset}"
  sleep 0.5
fi

draw_header

echo -e "${yellow}🛑 正在强制停止相关服务...${reset}"
systemctl stop mariadb
systemctl stop mysql
systemctl stop apache2
systemctl stop dovecot
systemctl stop postfix

echo -e "${yellow}🧹 正在清除数据库残留...${reset}"
dpkg --remove --force-remove-reinstreq mariadb-common
apt purge -y mariadb-* mysql* libmariadb3 galera-*
rm -rf /etc/mysql /var/lib/mysql /var/log/mysql /var/log/mariadb

# 卸载软件包
packages=(
  postfix dovecot-core dovecot-imapd dovecot-mysql dovecot-pop3d mailutils dovecot-sql
  mariadb-server apache2 certbot opendkim opendkim-tools
  php php-cli php-fpm php-mysql php-zip php-xml php-mbstring php-intl php-imap php-ldap php-gd php-imagick
)

for p in "${packages[@]}"; do
  uninstall_package "$p"
done

# 删除文件与目录
paths=(
  /etc/roundcube /var/www/html/roundcube /var/lib/mysql /etc/mysql
  /var/spool/postfix /etc/opendkim /etc/letsencrypt
  /var/log/mail.log /var/log/mail.err /var/log/dovecot.log
  /var/mail/vhosts
)

for p in "${paths[@]}"; do
  remove_path "$p"
done

remove_users

echo -e "\n🔍 ${yellow}清理系统残余组件...${reset}"
DEBIAN_FRONTEND=noninteractive apt autoremove -y
apt clean
echo -e "${green}✓ 系统清理完成${reset}"

draw_footer

if [ $fail_all -eq 0 ]; then
  echo -e "${green}✅ 邮局系统所有组件卸载成功！${reset}"
else
  echo -e "${red}⚠ 邮局系统卸载存在失败，请查看上方日志${reset}"
fi

read -p "$(echo -e "💬 ${cyan}按回车键返回菜单...${reset}")" dummy
bash /root/VPN/menu/mail.sh
