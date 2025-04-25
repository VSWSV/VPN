#!/bin/bash

INSTALL_DIR="/root/VPN/MAIL"
LOG_FILE="$INSTALL_DIR/install.log"
mkdir -p "$INSTALL_DIR" && chmod 700 "$INSTALL_DIR"
> "$LOG_FILE"

blue="\033[1;34m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
cyan="\033[1;36m"
reset="\033[0m"

real_progress() {
  local pid=$1
  local delay=0.2
  local spinstr='|/-\'
  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
    local temp=${spinstr#?}
    printf " [%c] " "$spinstr" 2>/dev/null
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b" 2>/dev/null
  done
  printf "    \b\b\b\b" 2>/dev/null
}

draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                   ${orange}📮 Roundcube邮局系统终极安装脚本 v4.2${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_separator() {
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

safe_clean() {

  [ -d "$INSTALL_DIR/roundcube" ] && rm -rf "$INSTALL_DIR/roundcube"
  [ -d "$INSTALL_DIR/roundcubemail-1.6.3" ] && rm -rf "$INSTALL_DIR/roundcubemail-1.6.3"
  [ -f "$INSTALL_DIR/roundcube.tar.gz" ] && rm -f "$INSTALL_DIR/roundcube.tar.gz"
}

install_step() {
  local step_name="$1"
  local install_cmd="$2"
  local max_retries=3
  local retry_count=0
  
  echo -e "${yellow}▶ ${step_name}...${reset}" | tee -a "$LOG_FILE"
  
  while [ $retry_count -lt $max_retries ]; do
    echo -ne "${blue}▷ 进度:${reset} "
    
    (eval "$install_cmd" >> "$LOG_FILE" 2>&1) &
    real_progress $!
    wait $!
    
    if [ $? -eq 0 ]; then
      printf "\r${green}✓ ${step_name}完成${reset}\n"
      return 0
    else
      ((retry_count++))
      printf "\r${yellow}⚠ 尝试 ${retry_count}/${max_retries} 失败${reset}\n"
      sleep 2
    fi
  done
  
  printf "\r${red}✗ ${step_name}失败${reset}\n"
  echo -e "${yellow}⚠ 错误日志: tail -n 20 $LOG_FILE${reset}" | tee -a "$LOG_FILE"
  return 1
}

# ------------------------- 主安装流程 -------------------------
main_install() {
  draw_header
  
  if ! command -v tree &>/dev/null; then
    install_step "安装tree工具" "apt install -y tree"
  fi

  install_step "系统环境检测" "
    [ \"$(id -u)\" != \"0\" ] && { echo '必须使用root权限'; exit 1; }
    grep -q 'Ubuntu 22.04' /etc/os-release || echo '⚠ 非Ubuntu 22.04系统'
  "

  install_step "安装邮件服务" "
    apt update -y &&
    DEBIAN_FRONTEND=noninteractive apt install -y \
      postfix postfix-mysql \
      dovecot-core dovecot-imapd dovecot-pop3d dovecot-mysql
  "

  install_step "安装Web服务" "
    apt install -y \
      apache2 libapache2-mod-php \
      php php-{mysql,intl,json,curl,zip,gd,mbstring,xml,imap}
  "

  safe_clean

  install_step "部署Webmail" "
    wget -q --tries=3 --timeout=30 https://github.com/roundcube/roundcubemail/releases/download/1.6.3/roundcubemail-1.6.3-complete.tar.gz -O $INSTALL_DIR/roundcube.tar.gz &&
    tar -xzf $INSTALL_DIR/roundcube.tar.gz -C $INSTALL_DIR &&
    mv $INSTALL_DIR/roundcubemail-1.6.3 $INSTALL_DIR/roundcube &&
    chown -R www-data:www-data $INSTALL_DIR/roundcube &&
    chmod -R 755 $INSTALL_DIR/roundcube &&
    rm -f $INSTALL_DIR/roundcube.tar.gz
  "


  install_step "配置Web访问" "
    ln -sfT $INSTALL_DIR/roundcube /var/www/roundcube &&
    systemctl restart apache2
  "

echo -e "${orange}📦 安装目录结构:${reset}"
if command -v tree &>/dev/null; then
  tree -L 2 "$INSTALL_DIR" | sed '
    s/directories/个目录/g;
    s/files/个文件/g;
    s/ directory/ 个目录/g;
    s/ file/ 个文件/g'
else
  ls -lhR "$INSTALL_DIR" | grep -v "^$"
  echo -e "${blue}（共 $(find "$INSTALL_DIR" -type d | wc -l) 个目录，$(find "$INSTALL_DIR" -type f | wc -l) 个文件）${reset}"
fi
  
  draw_separator
  echo -e "${orange}🔍 服务状态检查:${reset}"
  systemctl is-active postfix &>/dev/null && echo -e "${green}✓ Postfix运行正常${reset}" || echo -e "${red}✗ Postfix未运行${reset}"
  systemctl is-active dovecot &>/dev/null && echo -e "${green}✓ Dovecot运行正常${reset}" || echo -e "${red}✗ Dovecot未运行${reset}"
  systemctl is-active apache2 &>/dev/null && echo -e "${green}✓ Apache运行正常${reset}" || echo -e "${red}✗ Apache未运行${reset}"
  
  draw_footer
}

clear
main_install

# ======================== 最终交互 ========================
read -p "按回车返回主菜单..."
bash /root/VPN/menu/mail.sh
