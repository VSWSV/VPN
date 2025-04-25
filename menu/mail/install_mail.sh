#!/bin/bash

# ==============================================
# Roundcube邮局系统安装脚本（纯净色彩版）
# 版本：v4.6
# 最后更新：2023-10-27
# 特点：
#   1. 100%稳定的颜色输出
#   2. 完整的目录结构展示
#   3. 准确的中文统计
# ==============================================

# ------------------------- 初始化设置 -------------------------
INSTALL_DIR="/root/VPN/MAIL"
LOG_FILE="$INSTALL_DIR/install.log"
mkdir -p "$INSTALL_DIR" && chmod 700 "$INSTALL_DIR"
> "$LOG_FILE"

# ------------------------- 颜色定义（使用ANSI标准）-----------------
BLUE="\033[1;34m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
ORANGE="\033[38;5;214m"
CYAN="\033[1;36m"
MAGENTA="\033[1;35m"
RESET="\033[0m"

# ------------------------- 安全颜色输出函数 -------------------------
cecho() {
  local color=$1
  shift
  echo -e "${color}$*${RESET}"
}

# ------------------------- 目录树显示函数 -------------------------
show_dir_structure() {
  echo -e "${ORANGE}📦 安装目录结构:${RESET}"
  
  if command -v tree &>/dev/null; then
    # 使用tree命令（带颜色）
    echo -e "${BLUE}"
    tree -L 2 --noreport "$INSTALL_DIR"
    echo -e "${RESET}"
    
    # 获取统计信息并中文化
    local dir_count=$(find "$INSTALL_DIR" -type d | wc -l)
    local file_count=$(find "$INSTALL_DIR" -type f | wc -l)
    echo -e "${MAGENTA}$dir_count 个目录 ${CYAN}$file_count 个文件${RESET}"
  else
    # 备用ls方案
    echo -e "${BLUE}"
    ls -lhp "$INSTALL_DIR" | grep -v "^total"
    echo -e "${RESET}"
    
    local dir_count=$(find "$INSTALL_DIR" -type d | wc -l)
    local file_count=$(find "$INSTALL_DIR" -type f | wc -l)
    echo -e "${MAGENTA}$dir_count 个目录 ${CYAN}$file_count 个文件${RESET}"
  fi
}

# ------------------------- 进度动画 -------------------------
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

# ------------------------- 边框函数 -------------------------
draw_header() {
  echo -e "${CYAN}╔═════════════════════════════════════════════════════════════════════════════════╗${RESET}"
  cecho "$ORANGE" "                   📮 Roundcube邮局系统安装脚本 v4.6"
  echo -e "${CYAN}╠═════════════════════════════════════════════════════════════════════════════════╣${RESET}"
}

draw_separator() {
  echo -e "${CYAN}╠═════════════════════════════════════════════════════════════════════════════════╣${RESET}"
}

draw_footer() {
  echo -e "${CYAN}╚═════════════════════════════════════════════════════════════════════════════════╝${RESET}"
}

# ------------------------- 安装步骤 -------------------------
install_step() {
  local step_name="$1"
  local install_cmd="$2"
  
  cecho "$YELLOW" "▶ $step_name..."
  echo -ne "${BLUE}▷ 进度:${RESET} "
  
  (eval "$install_cmd" >> "$LOG_FILE" 2>&1) &
  progress_spinner $!
  wait $!
  
  if [ $? -eq 0 ]; then
    printf "\r${GREEN}✓ $step_name完成${RESET}\n"
    return 0
  else
    printf "\r${RED}✗ $step_name失败${RESET}\n"
    cecho "$YELLOW" "▶ 错误日志:"
    tail -n 5 "$LOG_FILE" | sed "s/error\|fail/${RED}&${RESET}/g"
    return 1
  fi
}

# ------------------------- 主安装流程 -------------------------
main_install() {
  clear
  draw_header
  
  # 0. 确保安装tree命令
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

  # 4. 部署Roundcube
  install_step "部署Webmail" "
    rm -rf $INSTALL_DIR/roundcube* &&
    wget -q --tries=3 --timeout=30 https://github.com/roundcube/roundcubemail/releases/download/1.6.3/roundcubemail-1.6.3-complete.tar.gz -O $INSTALL_DIR/roundcube.tar.gz &&
    tar -xzf $INSTALL_DIR/roundcube.tar.gz -C $INSTALL_DIR &&
    mv $INSTALL_DIR/roundcubemail-1.6.3 $INSTALL_DIR/roundcube &&
    chown -R www-data:www-data $INSTALL_DIR/roundcube &&
    chmod -R 755 $INSTALL_DIR/roundcube &&
    rm $INSTALL_DIR/roundcube.tar.gz
  "

  # 5. 配置Web访问
  install_step "配置Web访问" "
    ln -sf $INSTALL_DIR/roundcube /var/www/roundcube &&
    systemctl restart apache2
  "

  # 显示安装结果
  draw_separator
  show_dir_structure
  
  draw_separator
  cecho "$ORANGE" "🔍 服务状态检查:"
  systemctl is-active postfix &>/dev/null && cecho "$GREEN" "✓ Postfix运行正常" || cecho "$RED" "✗ Postfix未运行"
  systemctl is-active dovecot &>/dev/null && cecho "$GREEN" "✓ Dovecot运行正常" || cecho "$RED" "✗ Dovecot未运行"
  systemctl is-active apache2 &>/dev/null && cecho "$GREEN" "✓ Apache运行正常" || cecho "$RED" "✗ Apache未运行"
  
  draw_footer
}

# ======================== 执行安装 ========================
main_install

# ======================== 最终交互 ========================
read -p "按回车返回主菜单..."
bash /root/VPN/menu/mail.sh
