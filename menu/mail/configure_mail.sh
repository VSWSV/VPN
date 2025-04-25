#!/bin/bash

# ==============================================
# 邮件系统全功能配置脚本
# 版本：2.0
# 最后更新：2023-10-15
# ==============================================

# 基础配置
INSTALL_DIR="/root/VPN/MAIL"
CONFIG_FILE="/etc/postfix/main.cf"
DOVECOT_CONFIG="/etc/dovecot/dovecot.conf"
ROUNDCUBE_CONFIG="/var/www/roundcube/config/config.inc.php"
MYSQL_ROOT_PASS=""
DOMAIN=""
HOSTNAME=""

# 颜色定义
blue="\033[1;34m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
cyan="\033[1;36m"
magenta="\033[1;35m"
reset="\033[0m"

# 函数：彩色输出
cecho() {
  local color="$1"
  shift
  echo -e "${color}$*${reset}"
}

# 函数：显示分隔线
draw_line() {
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

# 函数：显示标题
draw_header() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "${orange}            📧 专业邮件系统配置向导            ${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

# 函数：显示页脚
draw_footer() {
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

# 函数：检查MySQL安装
check_mysql() {
  if ! command -v mysql &> /dev/null; then
    cecho "$yellow" "➤ 检测到MySQL未安装，正在自动安装..."
    apt update && apt install -y mysql-server
    if [ $? -ne 0 ]; then
      cecho "$red" "✗ MySQL安装失败！请手动安装后重试"
      exit 1
    fi
    mysql_secure_installation
    cecho "$green" "✓ MySQL安装完成"
  fi
}

# 函数：DNS配置指南
dns_guide() {
  draw_header
  cecho "$green" "                  🌐 DNS配置指南"
  draw_line
  
  cecho "$yellow" "请为您的域名添加以下DNS记录：\n"
  
  printf "${blue}%-10s ${yellow}%-12s ${green}%-30s${reset}\n" "类型" "主机" "值"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  printf "${green}%-10s ${reset}%-12s ${green}%-30s${reset}\n" "A" "@" "$(hostname -I | awk '{print $1}')"
  printf "${green}%-10s ${reset}%-12s ${green}%-30s${reset}\n" "A" "mail" "$(hostname -I | awk '{print $1}')"
  printf "${green}%-10s ${reset}%-12s ${green}%-30s${reset}\n" "MX" "@" "mail.$DOMAIN (优先级10)"
  printf "${green}%-10s ${reset}%-12s ${green}%-30s${reset}\n" "TXT" "@" "v=spf1 mx ~all"
  printf "${green}%-10s ${reset}%-12s ${green}%-30s${reset}\n" "TXT" "_dmarc" "v=DMARC1; p=none; rua=mailto:admin@$DOMAIN"
  
  cecho "$yellow" "\n🔔 重要提示："
  cecho "$blue" "1. 请将示例域名替换为您的实际域名"
  cecho "$blue" "2. PTR记录需联系服务器提供商设置"
  cecho "$blue" "3. 测试命令: dig MX $DOMAIN 或 nslookup mail.$DOMAIN"
  
  draw_footer
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

# 函数：主域名配置
setup_domain() {
  draw_header
  cecho "$green" "                 📧 主域名配置"
  draw_line
  
  read -p "$(echo -e "${yellow}➤ 请输入您的邮件主域名 (如 example.com): ${reset}")" DOMAIN
  read -p "$(echo -e "${yellow}➤ 请输入邮件服务器主机名 (如 mail.example.com): ${reset}")" HOSTNAME
  
  # 设置系统主机名
  hostnamectl set-hostname $HOSTNAME
  sed -i "s/^127.0.1.1.*/127.0.1.1\t$HOSTNAME/" /etc/hosts
  
  # Postfix配置
  cecho "$yellow" "⏳ 配置Postfix..."
  postconf -e "myhostname = $HOSTNAME"
  postconf -e "mydomain = $DOMAIN"
  postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
  postconf -e "home_mailbox = Maildir/"
  
  # Dovecot配置
  cecho "$yellow" "⏳ 配置Dovecot..."
  echo "ssl_cert = </etc/letsencrypt/live/$HOSTNAME/fullchain.pem" >> $DOVECOT_CONFIG
  echo "ssl_key = </etc/letsencrypt/live/$HOSTNAME/privkey.pem" >> $DOVECOT_CONFIG
  
  # Roundcube配置
  if [ -f $ROUNDCUBE_CONFIG ]; then
    sed -i "s/\$config\['default_host'\] = .*/\$config\['default_host'\] = 'ssl:\/\/$HOSTNAME';/" $ROUNDCUBE_CONFIG
    sed -i "s/\$config\['smtp_server'\] = .*/\$config\['smtp_server'\] = 'tls:\/\/$HOSTNAME';/" $ROUNDCUBE_CONFIG
  fi
  
  systemctl restart postfix dovecot
  
  cecho "$green" "\n✅ 主域名配置完成！"
  draw_footer
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

# 函数：数据库配置
setup_database() {
  draw_header
  cecho "$green" "                 🗃️ 数据库配置"
  draw_line
  
  check_mysql
  
  # 获取MySQL root密码
  while true; do
    read -p "$(echo -e "${yellow}➤ 请输入MySQL root密码: ${reset}")" -s MYSQL_ROOT_PASS
    echo
    if mysql -uroot -p"$MYSQL_ROOT_PASS" -e ";" 2>/dev/null; then
      break
    else
      cecho "$red" "✗ 密码错误，请重试"
    fi
  done
  
  DB_NAME="mail_$(date +%Y%m%d)"
  DB_USER="mail_admin"
  DB_PASS=$(openssl rand -base64 12)
  
  # 创建数据库
  mysql -uroot -p"$MYSQL_ROOT_PASS" <<MYSQL_SCRIPT
CREATE DATABASE $DB_NAME;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

  # 创建表结构
  mysql -uroot -p"$MYSQL_ROOT_PASS" $DB_NAME <<EOF
CREATE TABLE virtual_domains (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE virtual_users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  domain_id INT NOT NULL,
  email VARCHAR(100) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
);

CREATE TABLE virtual_aliases (
  id INT AUTO_INCREMENT PRIMARY KEY,
  domain_id INT NOT NULL,
  source VARCHAR(100) NOT NULL,
  destination VARCHAR(100) NOT NULL,
  FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
);

INSERT INTO virtual_domains (name) VALUES ('$DOMAIN');
EOF

  cecho "$green" "\n✅ 数据库配置完成！"
  cecho "$blue" "数据库名: $DB_NAME"
  cecho "$blue" "用户名: $DB_USER"
  cecho "$blue" "密码: $DB_PASS"
  
  draw_footer
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

# 函数：多域名配置
multi_domain() {
  draw_header
  cecho "$green" "                 🌍 多域名配置"
  draw_line
  
  cecho "$yellow" "当前主域名: $DOMAIN"
  
  # 显示已有域名
  cecho "$blue" "\n已配置域名列表:"
  mysql -uroot -p"$MYSQL_ROOT_PASS" $DB_NAME -e "SELECT name AS '域名' FROM virtual_domains;" 2>/dev/null
  
  echo -e "\n${green}1. 添加子域名"
  echo -e "${green}2. 设置全局收件"
  echo -e "${green}3. 返回主菜单${reset}"
  
  read -p "$(echo -e "${yellow}➤ 请选择操作 [1-3]: ${reset}")" choice
  
  case $choice in
    1)
      read -p "$(echo -e "${yellow}➤ 请输入子域名 (如 sales.$DOMAIN): ${reset}")" subdomain
      if [[ $subdomain =~ ^[a-zA-Z0-9.]+$ ]]; then
        mysql -uroot -p"$MYSQL_ROOT_PASS" $DB_NAME -e "INSERT INTO virtual_domains (name) VALUES ('$subdomain');"
        cecho "$green" "✅ 子域名 $subdomain 添加成功"
        cecho "$blue" "请为该子域名添加DNS MX记录指向 mail.$DOMAIN"
      else
        cecho "$red" "✗ 无效的子域名格式"
      fi
      ;;
    2)
      read -p "$(echo -e "${yellow}➤ 请输入全局收件邮箱 (如 catch@$DOMAIN): ${reset}")" catch_all
      mysql -uroot -p"$MYSQL_ROOT_PASS" $DB_NAME <<EOF
INSERT INTO virtual_aliases (domain_id, source, destination)
SELECT id, '@$DOMAIN', '$catch_all' FROM virtual_domains WHERE name='$DOMAIN';
EOF
      cecho "$green" "✅ 全局收件设置成功！所有发送到 *@$DOMAIN 的邮件将转发到 $catch_all"
      ;;
    3)
      return ;;
    *)
      cecho "$red" "✗ 无效选择" ;;
  esac
  
  draw_footer
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
  multi_domain
}

# 函数：邮箱账户管理
manage_accounts() {
  draw_header
  cecho "$green" "                 📨 邮箱账户管理"
  draw_line
  
  cecho "$yellow" "当前域名: $DOMAIN"
  
  echo -e "\n${green}1. 创建邮箱账户"
  echo -e "${green}2. 查看账户列表"
  echo -e "${green}3. 返回主菜单${reset}"
  
  read -p "$(echo -e "${yellow}➤ 请选择操作 [1-3]: ${reset}")" choice
  
  case $choice in
    1)
      read -p "$(echo -e "${yellow}➤ 请输入邮箱地址 (如 user@$DOMAIN): ${reset}")" email
      read -p "$(echo -e "${yellow}➤ 请输入密码: ${reset}")" -s password
      echo
      
      encrypted=$(doveadm pw -s SHA512-CRYPT -p "$password")
      domain_id=$(mysql -uroot -p"$MYSQL_ROOT_PASS" $DB_NAME -sN -e "SELECT id FROM virtual_domains WHERE name='$DOMAIN'")
      
      mysql -uroot -p"$MYSQL_ROOT_PASS" $DB_NAME -e "
      INSERT INTO virtual_users (domain_id, email, password) 
      VALUES ($domain_id, '$email', '$encrypted');"
      
      cecho "$green" "✅ 邮箱账户 $email 创建成功！"
      ;;
    2)
      cecho "$blue" "\n邮箱账户列表:"
      mysql -uroot -p"$MYSQL_ROOT_PASS" $DB_NAME -e "
      SELECT email AS '邮箱', 
      CONCAT(LEFT(password, 10), '...') AS '密码哈希' 
      FROM virtual_users;" 2>/dev/null || cecho "$red" "暂无邮箱账户"
      ;;
    3)
      return ;;
    *)
      cecho "$red" "✗ 无效选择" ;;
  esac
  
  draw_footer
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
  manage_accounts
}

# 函数：服务信息
service_info() {
  draw_header
  cecho "$green" "                 ℹ️ 服务访问信息"
  draw_line
  
  cecho "$yellow" "Webmail访问地址:"
  cecho "$blue" "https://$HOSTNAME/roundcube"
  
  cecho "$yellow" "\nSMTP服务器:"
  cecho "$blue" "地址: $HOSTNAME"
  cecho "$blue" "端口: 587 (STARTTLS), 465 (SSL)"
  
  cecho "$yellow" "\nIMAP服务器:"
  cecho "$blue" "地址: $HOSTNAME"
  cecho "$blue" "端口: 993 (SSL)"
  
  cecho "$yellow" "\n管理员邮箱:"
  cecho "$blue" "postmaster@$DOMAIN"
  
  draw_footer
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

# 主菜单
main_menu() {
  while true; do
    draw_header
    cecho "$green" "                 🏠 主菜单"
    draw_line
    
    echo -e "${green}1. DNS配置指南"
    echo -e "${green}2. 配置主域名"
    echo -e "${green}3. 数据库配置"
    echo -e "${green}4. 多域名管理"
    echo -e "${green}5. 邮箱账户管理"
    echo -e "${green}6. 服务访问信息"
    echo -e "${green}7. 退出脚本${reset}"
    draw_line
    
    read -p "$(echo -e "${yellow}➤ 请选择操作 [1-7]: ${reset}")" choice
    
    case $choice in
      1) dns_guide ;;
      2) setup_domain ;;
      3) setup_database ;;
      4) multi_domain ;;
      5) manage_accounts ;;
      6) service_info ;;
      7) 
        cecho "$green" "👋 感谢使用邮件系统配置脚本！"
        exit 0 ;;
      *) 
        cecho "$red" "✗ 无效选择，请重新输入"
        sleep 1 ;;
    esac
  done
}

main_menu
 
