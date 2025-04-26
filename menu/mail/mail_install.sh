#!/bin/bash
clear

# 颜色定义
cyan='\033[0;36m'
orange='\033[38;5;208m'
green='\033[0;32m'
red='\033[0;31m'
yellow='\033[1;33m'
reset='\033[0m'

# 获取服务器IP地址
server_ip=$(hostname -I | awk '{print $1}')

# 边框函数
top_border() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
}

middle_border() {
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

bottom_border() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 精确进度条
timed_progress() {
    local duration=$1
    local steps=20
    local delay=$(bc <<< "scale=2; $duration/$steps")
    echo -ne "${yellow}["
    for ((i=0; i<steps; i++)); do
        echo -ne "▓"
        sleep $delay
    done
    echo -e "]${reset}"
}

# 检查并单独安装包
install_single() {
    local pkg=$1
    dpkg -s "$pkg" &> /dev/null && {
        echo -e "${green}✓ ${pkg}已安装，跳过${reset}"
        return 0
    }

    echo -n "🔍 安装 ${pkg}..."
    if apt install -y $pkg > /dev/null 2>&1; then
        echo -e "\r${green}✓ ${pkg}安装成功${reset}          "
        return 0
    else
        echo -e "\r${red}✗ ${pkg}安装失败${reset}          "
        return 1
    fi
}

# 分类安装函数
install_category() {
    local category="$1"
    shift
    local packages=("$@")
    top_border
    echo -e "✦ ${orange}邮局系统安装${reset} ➔ ${cyan}${category}${reset}"
    middle_border

    timed_progress 3 &
    local progress_pid=$!

    for pkg in "${packages[@]}"; do
        install_single "$pkg" || {
            kill $progress_pid 2>/dev/null
            bottom_border
            read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
            bash /root/VPN/menu/mail.sh
            exit 1
        }
    done

    kill $progress_pid 2>/dev/null
    echo -e "${green}✓ ${category}组件全部就绪${reset}"
    bottom_border
    sleep 0.5
}

# 创建网站目录
if [ ! -d /var/www/html/roundcube ]; then
  top_border
  echo -e "✦ ${orange}准备安装环境${reset}"
  middle_border
  echo -e "${green}▶ 创建 /var/www/html/roundcube 目录${reset}"
  mkdir -p /var/www/html/roundcube
  chown -R www-data:www-data /var/www/html
  bottom_border
  sleep 1
else
  echo -e "${green}✓ Roundcube目录已存在，跳过创建${reset}"
fi

# 系统更新
top_border
echo -e "✦ ${orange}系统更新${reset}"
middle_border
echo -n "⏳ 更新进度: "
timed_progress 5 &
progress_pid=$!
apt update -y > /dev/null 2>&1
kill $progress_pid 2>/dev/null
echo -e "\r${green}✓ 系统更新完成${reset}          "
bottom_border
sleep 1

# 分类安装
install_category "邮件服务" postfix dovecot-core dovecot-imapd dovecot-mysql
install_category "数据库" mariadb-server
install_category "Web服务" apache2 php php-cli php-fpm
install_category "PHP扩展" php-mysql php-imap php-json php-intl php-gd
install_category "安全组件" opendkim opendkim-tools certbot

# 安装Roundcube到正确目录
top_border
echo -e "✦ ${orange}Roundcube安装${reset}"
middle_border

if [ ! -f /var/www/html/roundcube/index.php ]; then
  cd /tmp
  echo -e "📦 下载: ${yellow}roundcubemail-1.6.6${reset}"
  echo -n "⏳ 进度: "
  timed_progress 10 &
  if wget -qO roundcube.tar.gz https://github.com/roundcube/roundcubemail/releases/download/1.6.6/roundcubemail-1.6.6-complete.tar.gz; then
      tar -xzf roundcube.tar.gz
      rm -rf /var/www/html/roundcube/*
      mv roundcubemail-1.6.6/* /var/www/html/roundcube/
      rm -rf roundcubemail-1.6.6 roundcube.tar.gz
      chown -R www-data:www-data /var/www/html/roundcube
      kill $! 2>/dev/null
      echo -e "\r${green}✓ Roundcube安装完成 (路径: /var/www/html/roundcube)${reset}          "
  else
      kill $! 2>/dev/null
      echo -e "\r${red}✗ Roundcube下载失败${reset}          "
      bottom_border
      read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
      bash /root/VPN/menu/mail.sh
      exit 1
  fi
else
  echo -e "${green}✓ Roundcube已存在，跳过下载${reset}"
fi
bottom_border

# 完成提示
top_border
echo -e "✦ ${orange}邮局系统安装${reset}"
middle_border
echo -e "${green}🎉 所有组件安装完成！${reset}"
echo -e "${yellow}🔹 Roundcube路径: /var/www/html/roundcube${reset}"
echo -e "${yellow}🔹 访问地址: http://${server_ip}/roundcube${reset}"
echo -e "${yellow}🔹 数据库安全初始化：mariadb-secure-installation${reset}"
bottom_border

read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/mail.sh
