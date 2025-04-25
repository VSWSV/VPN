#!/bin/bash

# ==============================================
# Roundcube邮局系统完美安装脚本
# 版本：v4.4
# 最后更新：2023-10-26
# 修复内容：
#   1. 彻底解决颜色代码泄露问题
#   2. 完美中英文目录统计
#   3. 增强的错误处理
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
magenta="\033[1;35m"
reset="\033[0m"

# ------------------------- 彩色树状图函数 -------------------------
colored_tree() {
  # 先获取原始tree输出
  local raw_output=$(tree -L 2 -C --noreport "$1")
  
  # 颜色替换（确保在管道中处理）
  echo "$raw_output" | sed -E "
    # 替换目录行
    s/^([├└]── )([^.]*\/)$/\1${blue}\2${reset}/g;
    
    # 替换文件行
    s/^([├└]── )(.*\..*)$/\1${green}\2${reset}/g;
    
    # 替换统计信息
    s/([0-9]+) directories/${magenta}\1 个目录${reset}/g;
    s/([0-9]+) files/${cyan}\1 个文件${reset}/g;
    
    # 清理残留颜色代码
    s/\x1B\[[0-9;]*[mK]//g
  "
}

# ------------------------- 精确进度条 -------------------------
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

# ------------------------- 边框函数 -------------------------
draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                   ${orange}📮 Roundcube邮局系统安装脚本 v4.4${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_separator() {
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# ------------------------- 安装步骤 -------------------------
install_step() {
  local step_name="$1"
  local install_cmd="$2"
  
  echo -e "${yellow}▶ ${step_name}...${reset}" | tee -a "$LOG_FILE"
  echo -ne "${blue}▷ 进度:${reset} "
  
  (eval "$install_cmd" >> "$LOG_FILE" 2>&1) &
  real_progress $!
  wait $!
  
  if [ $? -eq 0 ]; then
    printf "\r${green}✓ ${step_name}完成${reset}\n"
    return 0
  else
    printf "\r${red}✗ ${step_name}失败${reset}\n"
    echo -e "${yellow}▶ 错误日志:${reset}"
    tail -n 5 "$LOG_FILE" | sed "s/error\|fail/${red}&${reset}/gi"
    return 1
  fi
}

# ------------------------- 主安装流程 -------------------------
main_install() {
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
  echo -e "${orange}📦 安装目录结构:${reset}"
  if command -v tree &>/dev/null; then
    colored_tree "$INSTALL_DIR"
  else
    ls -lh "$INSTALL_DIR" | awk '{
      if($1 ~ /^d/) printf "'${blue}'%s'${reset}'\n", $0;
      else printf "'${green}'%s'${reset}'\n", $0
    }'
    echo -e "${magenta}$(find "$INSTALL_DIR" -type d | wc -l) 个目录${reset}, ${cyan}$(find "$INSTALL_DIR" -type f | wc -l) 个文件${reset}"
  fi
  
  draw_separator
  echo -e "${orange}🔍 服务状态检查:${reset}"
  systemctl is-active postfix &>/dev/null && echo -e "${green}✓ Postfix运行正常${reset}" || echo -e "${red}✗ Postfix未运行${reset}"
  systemctl is-active dovecot &>/dev/null && echo -e "${green}✓ Dovecot运行正常${reset}" || echo -e "${red}✗ Dovecot未运行${reset}"
  systemctl is-active apache2 &>/dev/null && echo -e "${green}✓ Apache运行正常${reset}" || echo -e "${red}✗ Apache未运行${reset}"
  
  draw_footer
}

# ======================== 执行安装 ========================
clear
main_install

# ======================== 最终交互 ========================
read -p "按回车返回主菜单..."
bash /root/VPN/menu/mail.sh
