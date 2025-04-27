#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
clear

# 颜色定义
cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
reset="\033[0m"

# 边框函数
function draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                               ${orange}📦 邮局系统卸载${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}
function draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 密码确认
echo -e "${yellow}⚡ 卸载操作非常危险，需要输入密码确认${reset}"
read -p "请输入密码以继续（默认密码: 88）: " user_pass

if [ "$user_pass" != "88" ]; then
  echo -e "${red}❌ 密码错误，卸载已取消！${reset}"
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  sleep 0.5
  bash /root/VPN/menu/mail.sh
else
  echo -e "${green}✅ 密码正确，开始卸载！${reset}"
  sleep 0.5
fi

success_uninstall=0
fail_uninstall=0

draw_header

# 卸载的软件列表（完全根据你的安装版整理）
packages=(
postfix dovecot-core dovecot-imapd dovecot-mysql
mariadb-server
apache2
php php-cli php-fpm php-mysql php-imap php-json php-intl php-gd
opendkim opendkim-tools certbot
)

# 要删除的目录列表（也根据你的安装流程整理）
directories=(
/root/VPN/MAIL
/var/www/html/roundcube
/etc/postfix
/etc/dovecot
/etc/apache2
/etc/roundcube
)

# 卸载软件
for pkg in "${packages[@]}"; do
  echo -n "🔍 处理 ${pkg}..."
  if dpkg -s "$pkg" > /dev/null 2>&1; then
    apt purge -y "$pkg" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo -e "${green} ✓ 已卸载${reset}"
      success_uninstall=$((success_uninstall+1))
    else
      echo -e "${red} ✗ 卸载失败${reset}"
      fail_uninstall=$((fail_uninstall+1))
    fi
  else
    echo -e "${yellow} ⚠ 已不存在，跳过${reset}"
  fi
done

# 删除目录
for dir in "${directories[@]}"; do
  echo -n "🔍 删除 ${dir}..."
  if [ -d "$dir" ]; then
    rm -rf "$dir"
    if [ ! -d "$dir" ]; then
      echo -e "${green} ✓ 已删除${reset}"
      success_uninstall=$((success_uninstall+1))
    else
      echo -e "${red} ✗ 删除失败${reset}"
      fail_uninstall=$((fail_uninstall+1))
    fi
  else
    echo -e "${yellow} ⚠ 不存在，跳过${reset}"
  fi
done

# 清理残余
echo -n "🔍 清理残余缓存..."
apt autoremove -y > /dev/null 2>&1 && apt clean > /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo -e "${green} ✓ 完成${reset}"
else
  echo -e "${red} ✗ 失败${reset}"
fi

draw_footer

# 总结提示
if [ $fail_uninstall -eq 0 ]; then
  echo -e "${green}✅ 邮局系统所有组件卸载完成！${reset}"
else
  echo -e "${red}⚠ 邮局系统卸载部分失败，请检查上方日志${reset}"
fi

read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
