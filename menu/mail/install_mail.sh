#!/bin/bash

# ==============================================
# Roundcube邮局系统一键安装脚本（最终版）
# 版本：v3.2
# 最后更新：2023-10-25
# 特点：关键交互命令严格位于脚本末尾
# ==============================================

# ------------------------- 颜色定义 -------------------------
blue="\033[1;34m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
cyan="\033[1;36m"
reset="\033[0m"

# ------------------------- 边框函数 -------------------------
draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                         ${orange}📮 Roundcube 邮局系统一键安装脚本${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_separator() {
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# ------------------------- 功能函数 -------------------------
check_result() {
  [ $? -eq 0 ] && echo -e "${green}✓ 成功${reset}" || {
    echo -e "${red}✗ 失败（日志：/var/log/mail_install.log）${reset}"
    echo -e "${yellow}⚠ 使用 tail -n 20 /var/log/mail_install.log 查看错误${reset}"
    return 1
  }
}

check_system() {
  [ "$(id -u)" != "0" ] && { echo -e "${red}✗ 必须使用root权限执行${reset}"; exit 1; }
  grep -q "Ubuntu 22.04" /etc/os-release || {
    echo -e "${yellow}⚠ 非Ubuntu 22.04系统可能不兼容${reset}"
    read -p "是否继续？(y/n) " -n 1 -r
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    echo
  }
}

install_core() {
  echo -e "${yellow}▶ 安装核心组件...${reset}"
  apt update -y > /var/log/mail_install.log 2>&1 && \
  DEBIAN_FRONTEND=noninteractive apt install -y \
    postfix \
    postfix-mysql \
    dovecot-core \
    dovecot-imapd \
    dovecot-pop3d \
    dovecot-mysql >> /var/log/mail_install.log 2>&1
  check_result
}

install_web() {
  echo -e "${yellow}▶ 安装Web环境...${reset}"
  apt install -y \
    apache2 \
    libapache2-mod-php \
    php \
    php-{mysql,intl,json,curl,zip,gd,mbstring,xml,imap} >> /var/log/mail_install.log 2>&1 && \
  wget -q https://github.com/roundcube/roundcubemail/releases/download/1.6.3/roundcubemail-1.6.3-complete.tar.gz -O /tmp/roundcube.tar.gz && \
  tar -xzf /tmp/roundcube.tar.gz -C /var/www && \
  mv /var/www/roundcubemail-* /var/www/roundcube && \
  chown -R www-data:www-data /var/www/roundcube && \
  chmod -R 755 /var/www/roundcube && \
  rm /tmp/roundcube.tar.gz
  check_result
}

show_summary() {
  draw_separator
  echo -e "${orange}📦 已安装组件：${reset}"
  echo -e "${blue}• Postfix $(postconf -d | grep mail_version | cut -d= -f2)${reset}"
  echo -e "${blue}• Dovecot $(dovecot --version)${reset}"
  echo -e "${blue}• Apache $(apache2 -v | grep -oP 'Apache/\K[0-9.]+')${reset}"
  echo -e "${blue}• PHP $(php -v | grep -oP 'PHP \K[0-9.]+')${reset}"
  echo -e "${blue}• Roundcube 1.6.3${reset}"

  draw_separator
  echo -e "${orange}📌 后续步骤：${reset}"
  echo -e "1. 配置DNS记录："
  echo -e "   ${blue}mail.example.com IN A 您的服务器IP${reset}"
  echo -e "   ${blue}@ IN MX 10 mail.example.com.${reset}"
  echo -e "2. 编辑配置文件："
  echo -e "   ${yellow}/etc/postfix/main.cf${reset}"
  echo -e "   ${yellow}/etc/dovecot/dovecot.conf${reset}"
  echo -e "3. 完成安装："
  echo -e "   访问 ${green}http://服务器IP/roundcube/installer${reset}"
}

# ======================== 主执行流程 ========================
clear
draw_header
check_system
install_core
install_web
show_summary
draw_footer

# ======================== 严格位于脚本末尾 ========================
read -p "按回车返回主菜单..."
bash /root/VPN/menu/mail.sh
