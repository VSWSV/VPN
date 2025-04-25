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
  # 清理可能存在的旧安装
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
    
    # 显示动态进度图标
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

main_install() {
  draw_header
  
  # 0. 安装tree命令
  if ! command -v tree &>/dev/null; then
    install_step "安装tree工具" "apt install -y tree"
  fi

  # 1. 系统检测
  install_step "系统环境检测" "
    [ \"$(id -u)\" != \"0\" ] && { echo '必须使用root权限'; exit 1; }
    grep -q 'Ubuntu 22.04' /etc/os-release || echo '⚠ 非Ubuntu 22.04系统'
  "

  # 2. 安装核心组件
  install_step "安装邮件服务" "
    apt update -y &&
    DEBIAN_FRONTEND=noninteractive apt install -y \
      postfix postfix-mysql \
      dovecot-core dovecot-imapd dovecot-pop3d dovecot-mysql
  "

  # 3. 安装Web环境
  install_step "安装Web服务" "
    apt install -y \
      apache2 libapache2-mod-php \
      php php-{mysql,intl,json,curl,zip,gd,mbstring,xml,imap}
  "

  # 4. 安全清理
  safe_clean

  # 5. 部署Roundcube（增强版）
  install_step "部署Webmail" "
    wget -q --tries=3 --timeout=30 https://github.com/roundcube/roundcubemail/releases/download/1.6.3/roundcubemail-1.6.3-complete.tar.gz -O $INSTALL_DIR/roundcube.tar.gz &&
    tar -xzf $INSTALL_DIR/roundcube.tar.gz -C $INSTALL_DIR &&
    mv $INSTALL_DIR/roundcubemail-1.6.3 $INSTALL_DIR/roundcube &&
    chown -R www-data:www-data $INSTALL_DIR/roundcube &&
    chmod -R 755 $INSTALL_DIR/roundcube &&
    rm -f $INSTALL_DIR/roundcube.tar.gz
  "

  # 6. 创建符号链接
  install_step "配置Web访问" "
    ln -sfT $INSTALL_DIR/roundcube /var/www/roundcube &&
    systemctl restart apache2
  "

# 显示安装结果
draw_separator
echo -e "${orange}📦 安装目录结构:${reset}"

if command -v tree &>/dev/null; then
  tree_output=$(tree -L 2 "$INSTALL_DIR")
  echo "$tree_output"
  
  dirs=$(echo "$tree_output" | grep -o '[0-9]\+ directories' | grep -o '[0-9]\+')
  files=$(echo "$tree_output" | grep -o '[0-9]\+ files' | grep -o '[0-9]\+')

  if [[ -n "$dirs" && -n "$files" ]]; then
    echo -e "共计：\033[1;95m${dirs}\033[0m \033[1;33m个目录\033[0m，\033[1;95m${files}\033[0m \033[1;33m个文件\033[0m"
  else
    echo -e "${red}✗ 无法解析目录和文件数量，请检查 tree 输出是否正常${reset}"
  fi
else
  echo -e "${yellow}⚠ 未安装 tree，使用 ls 替代显示：${reset}"
  ls -lhR "$INSTALL_DIR" | grep -v "^$"
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

read -p "按回车返回主菜单..."
bash /root/VPN/menu/mail.sh
