#!/bin/bash

# ==============================================
# Roundcube邮局系统完美安装脚本
# 版本：v4.5
# 最后更新：2023-10-26
# 特点：
#   1. 100%无颜色代码泄露
#   2. 完整的彩色目录树
#   3. 准确的中文统计
# ==============================================

# ------------------------- 初始化设置 -------------------------
INSTALL_DIR="/root/VPN/MAIL"
LOG_FILE="$INSTALL_DIR/install.log"
mkdir -p "$INSTALL_DIR" && chmod 700 "$INSTALL_DIR"
> "$LOG_FILE"

# ------------------------- 颜色定义 -------------------------
# 使用tput更安全的颜色定义
BLUE=$(tput setaf 4)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
RED=$(tput setaf 1)
ORANGE=$(tput setaf 208)
CYAN=$(tput setaf 6)
MAGENTA=$(tput setaf 5)
RESET=$(tput sgr0)

# ------------------------- 安全彩色输出函数 -------------------------
color_echo() {
  local color=$1
  shift
  echo "${color}$*${RESET}"
}

# ------------------------- 彩色目录树函数 -------------------------
safe_colored_tree() {
  # 先获取原始tree输出（禁用颜色）
  local raw_output=$(tree -L 2 --noreport "$1")
  
  # 处理输出
  while IFS= read -r line; do
    case $line in
      *DIRECTORY*)
        count=${line%% *}
        color_echo "$MAGENTA" "${line//$count directories/$count 个目录}"
        ;;
      *file*)
        count=${line%% *}
        color_echo "$CYAN" "${line//$count files/$count 个文件}"
        ;;
      *──\ */*)
        color_echo "$BLUE" "$line"
        ;;
      *──\ *.*)
        color_echo "$GREEN" "$line"
        ;;
      *)
        echo "$line"
        ;;
    esac
  done <<< "$raw_output"
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
  echo "${CYAN}╔═════════════════════════════════════════════════════════════════════════════════╗${RESET}"
  color_echo "$ORANGE" "                   📮 Roundcube邮局系统安装脚本 v4.5"
  echo "${CYAN}╠═════════════════════════════════════════════════════════════════════════════════╣${RESET}"
}

draw_separator() {
  echo "${CYAN}╠═════════════════════════════════════════════════════════════════════════════════╣${RESET}"
}

draw_footer() {
  echo "${CYAN}╚═════════════════════════════════════════════════════════════════════════════════╝${RESET}"
}

# ------------------------- 安装步骤 -------------------------
install_step() {
  local step_name="$1"
  local install_cmd="$2"
  
  color_echo "$YELLOW" "▶ $step_name..."
  echo -n "${BLUE}▷ 进度:${RESET} "
  
  (eval "$install_cmd" >> "$LOG_FILE" 2>&1) &
  progress_spinner $!
  wait $!
  
  if [ $? -eq 0 ]; then
    printf "\r${GREEN}✓ $step_name完成${RESET}\n"
    return 0
  else
    printf "\r${RED}✗ $step_name失败${RESET}\n"
    color_echo "$YELLOW" "▶ 错误日志:"
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
    wget -q https://github.com/roundcube/roundcubemail/releases/download/1.6.3/roundcubemail-1.6.3-complete.tar.gz -O $INSTALL_DIR/roundcube.tar.gz &&
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
  color_echo "$ORANGE" "📦 安装目录结构:"
  if command -v tree &>/dev/null; then
    safe_colored_tree "$INSTALL_DIR"
  else
    ls -lh "$INSTALL_DIR" | awk -v blue="$BLUE" -v green="$GREEN" -v reset="$RESET" '{
      if($1 ~ /^d/) print blue $0 reset;
      else print green $0 reset
    }'
    color_echo "$MAGENTA" "$(find "$INSTALL_DIR" -type d | wc -l) 个目录"
    color_echo "$CYAN" "$(find "$INSTALL_DIR" -type f | wc -l) 个文件"
  fi
  
  draw_separator
  color_echo "$ORANGE" "🔍 服务状态检查:"
  systemctl is-active postfix &>/dev/null && color_echo "$GREEN" "✓ Postfix运行正常" || color_echo "$RED" "✗ Postfix未运行"
  systemctl is-active dovecot &>/dev/null && color_echo "$GREEN" "✓ Dovecot运行正常" || color_echo "$RED" "✗ Dovecot未运行"
  systemctl is-active apache2 &>/dev/null && color_echo "$GREEN" "✓ Apache运行正常" || color_echo "$RED" "✗ Apache未运行"
  
  draw_footer
}

# ======================== 执行安装 ========================
main_install

# ======================== 最终交互 ========================
read -p "按回车返回主菜单..."
bash /root/VPN/menu/mail.sh
