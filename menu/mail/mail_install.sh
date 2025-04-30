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
  echo -e "                                 ${orange}📬 邮局系统安装${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

echo -e "${yellow}⚡ 安装操作需要输入密码确认${reset}"
read -p "请输入密码以继续（默认密码: 88）: " user_pass

if [ "$user_pass" != "88" ]; then
  echo -e "${red}❌ 密码错误，安装已取消！${reset}"
  sleep 0.5
  bash /root/VPN/menu/mail.sh
  exit 1
else
  echo -e "${green}✅ 密码正确，开始安装！${reset}"
  sleep 0.5
fi

install_single() {
  local pkg=$1
  echo -n "🔍 安装 ${pkg}..."
  if DEBIAN_FRONTEND=readline apt install "$pkg"; then
    echo -e "${green} ✓ 安装成功${reset}"
    return 0
  else
    echo -e "${red} ✗ 安装失败${reset}"
    return 1
  fi
}

install_category() {
  local title="$1"
  shift
  local packages=("$@")
  local success_count=0
  local fail_count=0

  echo -e "${yellow}${title}${reset}"

  for pkg in "${packages[@]}"; do
    install_single "$pkg"
    if [ $? -eq 0 ]; then
      success_count=$((success_count+1))
    else
      fail_count=$((fail_count+1))
    fi
  done

  success_all=$((success_all+success_count))
  fail_all=$((fail_all+fail_count))

  if [ $fail_count -eq 0 ]; then
    echo -e "${green}✅ ${title}全部安装成功${reset}\n"
  else
    echo -e "${red}⚠ ${title}安装部分失败（成功${success_count}个，失败${fail_count}个）${reset}\n"
  fi
}

draw_header

echo -e "${green}▶ 更新系统源中...${reset}"
apt update && echo -e "${green}✅ 系统更新完成${reset}" || echo -e "${red}❌ 系统更新失败${reset}"
sleep 1

install_category "📦 安装邮件服务组件..." postfix dovecot-core dovecot-imapd dovecot-mysql mailutils dovecot-pop3d
install_category "🛢️ 安装数据库服务..." mariadb-server
install_category "🌐 安装Web服务器..." apache2
install_category "🧩 安装PHP及扩展..." php php-cli php-fpm php-mysql php-curl php-zip php-xml php-mbstring php-intl php-gd php-imap php-ldap php-imagick
install_category "🔒 安装邮件认证和HTTPS工具..." opendkim opendkim-tools certbot

success_roundcube=0
fail_roundcube=0

echo -e "${yellow}📬 安装Roundcube...${reset}"
cd /var/www/html

echo -n "🔍 下载 Roundcube源码..."
if wget -O roundcube.tar.gz https://github.com/roundcube/roundcubemail/releases/download/1.6.6/roundcubemail-1.6.6-complete.tar.gz; then
  echo -e "${green} ✓ 成功${reset}"
  success_roundcube=$((success_roundcube+1))
else
  echo -e "${red} ✗ 失败${reset}"
  fail_roundcube=$((fail_roundcube+1))
fi
fail_all=$((fail_all+fail_roundcube))
echo -e "${yellow}🔍 解压 Roundcube源码...${reset}"
if tar -xzf roundcube.tar.gz; then
  echo -e "${green} ✓ 成功${reset}"
  success_roundcube=$((success_roundcube+1))
else
  echo -e "${red} ✗ 失败${reset}"
  fail_roundcube=$((fail_roundcube+1))
fi

if [ -d "roundcubemail-1.6.6" ]; then
  [ -d "roundcube" ] && rm -rf roundcube
  mv roundcubemail-1.6.6 roundcube
fi

echo -e "${yellow}🛠️ 修复 Roundcube目录权限...${reset}"
if [ -d "/var/www/html/roundcube" ]; then
  chown -R www-data:www-data /var/www/html/roundcube && echo -e "${green} ✓ 成功${reset}" || {
    echo -e "${red} ✗ 失败${reset}"
    fail_roundcube=$((fail_roundcube+1))
  }
else
  echo -e "${red} ✗ 失败${reset}"
  fail_roundcube=$((fail_roundcube+1))
fi
apt install php-xml

rm -f /var/www/html/roundcube.tar.gz

php_version=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
php_ini="/etc/php/${php_version}/apache2/php.ini"

if [ -f "$php_ini" ]; then
    echo -e "${yellow}🛠️ 正在设置PHP时区为 中国标准时间（Asia/Shanghai）...${reset}"
    sed -i "s@^;date.timezone =@date.timezone = Asia/Shanghai@" "$php_ini"
    systemctl restart apache2
    echo -e "${green} ✓ 成功${reset}"
else
    echo -e "${red}✖ 未找到 $php_ini，请确认 PHP 是否安装或 Apache PHP 模块是否正确安装${reset}"
fi


ip=$(curl -s ipv4.ip.sb)
echo -e "${yellow}🔗 Roundcube安装器入口: ${green}http://${ip}/roundcube/installer/${reset}"

if [ $fail_all -eq 0 ]; then
  echo -e "${green}🎉 邮局系统所有组件安装成功！${reset}"
else
  echo -e "${red}⚠ 邮局系统安装部分失败，请检查上方安装日志${reset}"
fi

draw_footer

read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
