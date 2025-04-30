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
  echo -e "                               ${orange}📦 邮局系统卸载 FINAL${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

function uninstall_package() {
  local pkg=$1
  echo -n "🔍 处理 ${pkg}..."
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    apt purge -y "$pkg" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo -e "${green} ✓ 已卸载${reset}"
      success_all=$((success_all+1))
    else
      echo -e "${red} ✗ 卸载失败${reset}"
      fail_all=$((fail_all+1))
    fi
  else
    echo -e "${yellow} ⚠ 已不存在，跳过${reset}"
  fi
}

function remove_path() {
  local path=$1
  echo -n "🔍 删除 ${path}..."
  if [ -e "$path" ]; then
    rm -rf "$path"
    if [ ! -e "$path" ]; then
      echo -e "${green} ✓ 已删除${reset}"
      success_all=$((success_all+1))
    else
      echo -e "${red} ✗ 删除失败${reset}"
      fail_all=$((fail_all+1))
    fi
  else
    echo -e "${yellow} ⚠ 不存在，跳过${reset}"
  fi
}

function remove_users() {
  echo -n "🔍 清理系统用户 vmail / opendkim..."
  deluser --remove-home vmail >/dev/null 2>&1
  delgroup vmail >/dev/null 2>&1
  deluser opendkim >/dev/null 2>&1
  delgroup opendkim >/dev/null 2>&1
  echo -e "${green} ✓ 已处理${reset}"
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

# 卸载所有包
packages=(
  postfix dovecot-core dovecot-imapd dovecot-mysql dovecot-pop3d mailutils
  mariadb-server apache2 certbot opendkim opendkim-tools
  php php-cli php-fpm php-mysql php-zip php-xml php-mbstring php-intl php-imap php-ldap php-gd php-imagick
)

for p in "${packages[@]}"; do
  uninstall_package "$p"
done

# 删除目录和文件
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

echo -n "🔍 清理系统残余..."
apt autoremove -y >/dev/null 2>&1 && apt clean >/dev/null 2>&1
echo -e "${green} ✓ 完成${reset}"

draw_footer

if [ $fail_all -eq 0 ]; then
  echo -e "${green}✅ 邮局系统所有组件卸载完成！${reset}"
else
  echo -e "${red}⚠ 邮局系统卸载部分失败，请检查上方日志${reset}"
fi

read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
