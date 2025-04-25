#!/bin/bash

INSTALL_DIR="/root/VPN/MAIL"
LOG_FILE="$INSTALL_DIR/install.log"
mkdir -p "$INSTALL_DIR" && chmod 700 "$INSTALL_DIR"
> "$LOG_FILE"

# 颜色定义
blue="\033[1;34m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
cyan="\033[1;36m"
magenta="\033[1;35m"
reset="\033[0m"

cecho() {
  local color=$1
  shift
  echo -e "${color}$*${reset}"
}

show_dir_structure() {
  echo -e "${orange}📦 安装目录结构:${reset}"
  if command -v tree &>/dev/null; then
    echo -e "${blue}"
    tree -L 2 --noreport "$INSTALL_DIR"
    echo -e "${reset}"
    local dir_count=$(find "$INSTALL_DIR" -type d | wc -l)
    local file_count=$(find "$INSTALL_DIR" -type f | wc -l)
    echo -ne "${blue}${dir_count} 个目录${reset}  "
    echo -e "${green}${file_count} 个文件${reset}"
  else
    echo -e "${blue}"
    ls -lhp "$INSTALL_DIR" | grep -v "^total"
    echo -e "${reset}"
    local dir_count=$(find "$INSTALL_DIR" -type d | wc -l)
    local file_count=$(find "$INSTALL_DIR" -type f | wc -l)
    echo -ne "${blue}${dir_count} 个目录${reset}  "
    echo -e "${green}${file_count} 个文件${reset}"
  fi

  if [ -d "$INSTALL_DIR/roundcube/roundcube" ]; then
    cecho "$red" "🔴 检测到异常目录：roundcube/roundcube（请检查）"
  fi
}

progress_spinner() {
  local pid=$1
  local delay=0.2
  local spinstr='|/-\'
  while ps -p $pid > /dev/null; do
    printf " [%c] " "$spinstr"
    spinstr=${spinstr#?}${spinstr%???}
    sleep $delay
    printf "\b\b\b\b\b"
  done
  printf "    \b\b\b\b"
}

draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 📮 邮局系统安装${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_separator() {
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

install_step() {
  local step_name="$1"
  local install_cmd="$2"
  cecho "$yellow" "▶ $step_name..."
  echo -ne "${blue}▷ 进度:${reset} "
  (eval "$install_cmd" >> "$LOG_FILE" 2>&1) &
  progress_spinner $!
  wait $!
  if [ $? -eq 0 ]; then
    printf "\r${green}✓ $step_name完成${reset}\n"
    return 0
  else
    printf "\r${red}✗ $step_name失败${reset}\n"
    cecho "$yellow" "▶ 错误日志:"
    tail -n 10 "$LOG_FILE" | grep -Ei "error|fail|cp:|cannot|denied" | sed "s/error\|fail\|cp:\|cannot\|denied/${red}&${reset}/g"
    return 1
  fi
}

main_install() {
  clear
  draw_header
  rm -rf "$INSTALL_DIR/roundcube"
  rm -rf "/var/www/roundcube"
  mkdir -p "$INSTALL_DIR/roundcube"
  
  if ! command -v tree &>/dev/null; then
    install_step "① 安装tree工具" "apt install -y tree"
  fi
  
  install_step "② 系统环境检测" "[ \"$(id -u)\" != \"0\" ] && { echo '必须使用root权限'; exit 1; }; grep -q 'Ubuntu 22.04' /etc/os-release || echo '⚠ 非Ubuntu 22.04系统'"
  
  install_step "③ 安装邮件服务" "apt update -y && DEBIAN_FRONTEND=noninteractive apt install -y postfix postfix-mysql dovecot-core dovecot-imapd dovecot-pop3d dovecot-mysql"
  
  install_step "④ 安装Web服务" "apt install -y apache2 libapache2-mod-php php php-{mysql,intl,json,curl,zip,gd,mbstring,xml,imap}"
  
  install_step "⑤ 部署Webmail" "wget -q --tries=3 --timeout=30 https://github.com/roundcube/roundcubemail/releases/download/1.6.3/roundcubemail-1.6.3-complete.tar.gz -O $INSTALL_DIR/roundcube.tar.gz && tar -xzf $INSTALL_DIR/roundcube.tar.gz -C $INSTALL_DIR/roundcube --strip-components=1 && chown -R www-data:www-data $INSTALL_DIR/roundcube && chmod -R 755 $INSTALL_DIR/roundcube && rm $INSTALL_DIR/roundcube.tar.gz"
  
  install_step "⑥ 配置Web访问" "cp -r $INSTALL_DIR/roundcube /var/www/roundcube && systemctl restart apache2"
  
  draw_separator
  show_dir_structure
  draw_separator
  
  cecho "$orange" "🔍 服务状态检查:"
  systemctl is-active postfix &>/dev/null && cecho "$green" "✓ Postfix运行正常" || cecho "$red" "✗ Postfix未运行"
  systemctl is-active dovecot &>/dev/null && cecho "$green" "✓ Dovecot运行正常" || cecho "$red" "✗ Dovecot未运行"
  systemctl is-active apache2 &>/dev/null && cecho "$green" "✓ Apache运行正常" || cecho "$red" "✗ Apache未运行"
  
  draw_footer
  
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  bash /root/VPN/menu/mail.sh
}

main_install
