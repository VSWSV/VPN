#!/bin/bash
clear

# 颜色定义
cyan='\033[0;36m'
orange='\033[38;5;208m'
green='\033[0;32m'
red='\033[0;31m'
yellow='\033[1;33m'
reset='\033[0m'

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

# 安装状态检查
pkg_installed() {
    dpkg -l | grep -q "^ii  $1 " && return 0 || return 1
}

dir_exists() {
    [ -d "$1" ] && return 0 || return 1
}

# 安全安装函数
safe_install() {
    local pkg=$1
    if pkg_installed "$pkg"; then
        echo -e "${yellow}⏩ $pkg 已安装，跳过${reset}"
        return 0
    fi

    echo -n "🔍 安装 $pkg..."
    if apt install -y $pkg > /dev/null 2>&1; then
        echo -e "\r${green}✓ $pkg 安装成功${reset}          "
        return 0
    else
        echo -e "\r${red}✗ $pkg 安装失败${reset}          "
        return 1
    fi
}

# 分类安装控制
install_category() {
    local category="$1"
    shift
    local packages=("$@")
    
    top_border
    echo -e "✦ ${orange}邮局系统安装${reset} ➔ ${cyan}$category${reset}"
    middle_border

    for pkg in "${packages[@]}"; do
        safe_install "$pkg" || {
            bottom_border
            echo -e "${red}⚠ 关键组件安装失败，终止执行${reset}"
            read -p "$(echo -e "💬 ${cyan}按回车键返回主菜单...${reset}")" dummy
            bash /root/VPN/menu/mail.sh
            exit 1
        }
    done

    bottom_border
    sleep 0.5
}

# 准备环境
top_border
echo -e "✦ ${orange}准备安装环境${reset}"
middle_border
mkdir -p /var/www/html/roundcube
chown -R www-data:www-data /var/www/html
bottom_border

# 系统更新
top_border
echo -e "✦ ${orange}系统更新${reset}"
middle_border
apt update -y
bottom_border

# 分类安装
install_category "邮件服务" postfix dovecot-core dovecot-imapd dovecot-mysql
install_category "数据库" mariadb-server
install_category "Web服务" apache2 php php-cli php-fpm
install_category "PHP扩展" php-mysql php-imap php-json php-intl php-gd
install_category "安全组件" opendkim opendkim-tools certbot

# Roundcube安装
top_border
echo -e "✦ ${orange}Roundcube安装${reset}"
middle_border

if dir_exists "/var/www/html/roundcube/config"; then
    echo -e "${yellow}⏩ Roundcube 已存在，跳过安装${reset}"
else
    echo -e "📦 下载 Roundcube..."
    cd /var/www/html
    rm -rf roundcube.tar.gz roundcubemail-*
    
    if wget -qO roundcube.tar.gz https://github.com/roundcube/roundcubemail/releases/download/1.6.6/roundcubemail-1.6.6-complete.tar.gz; then
        tar -xzf roundcube.tar.gz
        mv roundcubemail-1.6.6 roundcube
        chown -R www-data:www-data roundcube
        rm -f roundcube.tar.gz
        echo -e "${green}✓ Roundcube 安装完成${reset}"
    else
        echo -e "${red}✗ Roundcube 下载失败${reset}"
        read -p "$(echo -e "💬 ${cyan}按回车键返回主菜单...${reset}")" dummy
        bash /root/VPN/menu/mail.sh
        exit 1
    fi
fi

bottom_border

# 完成提示
top_border
echo -e "✦ ${orange}安装完成${reset}"
middle_border
echo -e "${green}✅ 所有组件已就绪"
echo -e "${yellow}🔹 访问地址: http://your-server-ip/roundcube"
echo -e "${yellow}🔹 需要手动执行: mariadb-secure-installation"
bottom_border

# 保留的宝贝交互
read -p "$(echo -e "💬 ${cyan}按回车键返回主菜单...${reset}")" dummy
bash /root/VPN/menu/mail.sh
