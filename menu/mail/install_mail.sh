#!/bin/bash

# ==============================================
# Roundcube邮局系统终极安装脚本
# 版本：v4.0
# 最后更新：2023-10-25
# 特点：
#   - 安装到/root/VPN/MIAL
#   - 实时进度条显示
#   - 自动目录创建和权限设置
# ==============================================

# ------------------------- 初始化设置 -------------------------
INSTALL_DIR="/root/VPN/MAIL"
LOG_FILE="$INSTALL_DIR/install.log"
mkdir -p "$INSTALL_DIR" && chmod 700 "$INSTALL_DIR"
> "$LOG_FILE"

# ------------------------- 颜色定义 -------------------------
blue="\033[1;34m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
cyan="\033[1;36m"
reset="\033[0m"

# ------------------------- 进度条函数 -------------------------
progress_bar() {
  local duration=$1
  local steps=20
  for ((i=0; i<=steps; i++)); do
    printf "${blue}["
    printf "%.0s=" $(seq 1 $i)
    printf "%.0s " $(seq $((i+1)) $steps)
    printf "] ${yellow}%3d%%${reset}\r" $((i*100/steps))
    sleep "$duration"
  done
  printf "\n"
}

# ------------------------- 边框函数 -------------------------
draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                   ${orange}📮 Roundcube邮局系统终极安装脚本 v4.0${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_separator() {
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# ------------------------- 核心安装函数 -------------------------
install_step() {
  local step_name="$1"
  local install_cmd="$2"
  
  echo -e "${yellow}▶ ${step_name}...${reset}" | tee -a "$LOG_FILE"
  echo -e "${blue}▷ 进度:${reset}"
  progress_bar 0.2 &
  pid=$!
  
  if eval "$install_cmd" >> "$LOG_FILE" 2>&1; then
    kill $pid 2>/dev/null
    printf "\r${green}✓ ${step_name}完成${reset}\n"
    return 0
  else
    kill $pid 2>/dev/null
    printf "\r${red}✗ ${step_name}失败${reset}\n"
    echo -e "${yellow}⚠ 查看日志: tail -n 20 $LOG_FILE${reset}" | tee -a "$LOG_FILE"
    return 1
  fi
}

# ------------------------- 主安装流程 -------------------------
main_install() {
  draw_header
  
  # 1. 系统检测
  install_step "检测系统环境" "
    [ \"$(id -u)\" != \"0\" ] && { echo '必须使用root权限'; exit 1; }
    grep -q 'Ubuntu 22.04' /etc/os-release || echo '⚠ 非Ubuntu 22.04系统'
  "

  # 2. 安装核心组件
  install_step "安装Postfix+Dovecot" "
    apt update -y &&
    DEBIAN_FRONTEND=noninteractive apt install -y \
      postfix postfix-mysql \
      dovecot-core dovecot-imapd dovecot-pop3d dovecot-mysql
  "

  # 3. 安装Web环境
  install_step "安装Apache+PHP" "
    apt install -y \
      apache2 libapache2-mod-php \
      php php-{mysql,intl,json,curl,zip,gd,mbstring,xml,imap}
  "

  # 4. 安装Roundcube
  install_step "部署Roundcube" "
    wget -q https://github.com/roundcube/roundcubemail/releases/download/1.6.3/roundcubemail-1.6.3-complete.tar.gz -O $INSTALL_DIR/roundcube.tar.gz &&
    tar -xzf $INSTALL_DIR/roundcube.tar.gz -C $INSTALL_DIR &&
    mv $INSTALL_DIR/roundcubemail-* $INSTALL_DIR/roundcube &&
    chown -R www-data:www-data $INSTALL_DIR/roundcube &&
    chmod -R 755 $INSTALL_DIR/roundcube &&
    rm $INSTALL_DIR/roundcube.tar.gz
  "

  # 5. 创建符号链接
  install_step "配置Web访问" "
    ln -sf $INSTALL_DIR/roundcube /var/www/roundcube
  "

  # 显示结果
  draw_separator
  echo -e "${orange}📦 安装目录结构:${reset}"
  tree -L 2 "$INSTALL_DIR"
  
  draw_separator
  echo -e "${orange}🔍 服务状态检查:${reset}"
  systemctl is-active --quiet postfix && echo -e "${green}✓ Postfix运行中${reset}" || echo -e "${red}✗ Postfix未运行${reset}"
  systemctl is-active --quiet dovecot && echo -e "${green}✓ Dovecot运行中${reset}" || echo -e "${red}✗ Dovecot未运行${reset}"
  
  draw_footer
}

# ======================== 执行安装 ========================
clear
main_install

# ======================== 最终交互 ========================
read -p "按回车返回主菜单..."
bash /root/VPN/menu/mail.sh
