#!/bin/bash

blue="\033[1;34m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
reset="\033[0m"

echo -e "${blue}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "                   ${orange}📦 Roundcube 邮局系统依赖与环境安装（纯安装版）${reset}"
echo -e "${blue}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

# 更新系统
echo -e "  ▶ 正在更新软件源..."
apt update -y && apt upgrade -y

# 安装 Roundcube 所需依赖组件
echo -e "  ▶ 正在安装 Roundcube 所需组件..."
apt install -y \
apache2 mariadb-server mariadb-client \
php php-cli php-mysql php-common php-curl php-gd php-imagick php-intl php-mbstring php-xml php-zip php-sqlite3 php-bz2 php-pear \
libapache2-mod-php unzip wget curl gnupg \
imagemagick ghostscript fontconfig fonts-dejavu-core fonts-droid-fallback fonts-noto-mono fonts-urw-base35 \
ssl-cert

# 安装邮件服务组件
echo -e "  ▶ 正在安装邮件服务组件（Postfix + Dovecot）..."
debconf-set-selections <<< "postfix postfix/mailname string mail.example.com"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
apt install -y postfix dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-mysql

# 创建安装目录
install_dir="/var/www/html/roundcube"
mkdir -p "$install_dir"
cd "$install_dir" || exit

# 下载 Roundcube 最新版本
echo -e "  ▶ 正在下载 Roundcube 最新版本..."
latest_url=$(curl -s https://roundcube.net/download | grep -Eo 'https://.*roundcubemail.*complete.*tar\.gz' | head -n 1)
if [[ -z "$latest_url" ]]; then
  echo -e "  ${red}❌ 无法获取 Roundcube 最新版本下载链接，请检查网络或稍后重试。${reset}"
  exit 1
fi
wget "$latest_url" -O roundcube.tar.gz

# 解压安装文件
echo -e "  ▶ 正在解压安装文件..."
tar -xzf roundcube.tar.gz --strip-components=1
rm -f roundcube.tar.gz

# 设置权限
echo -e "  ▶ 正在设置权限..."
chown -R www-data:www-data "$install_dir"
chmod -R 755 "$install_dir"

echo -e "${green}✅ Roundcube 邮局系统安装完成，依赖与服务组件全部安装就绪。${reset}"
echo -e "${blue}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
echo -e "${yellow}🔧 请使用配置脚本或 Web 安装向导完成数据库设置与监听端口配置。${reset}"
