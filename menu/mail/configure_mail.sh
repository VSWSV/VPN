#!/bin/bash

# ==============================================
# 专业邮件系统配置脚本
# 版本：4.0
# 更新日期：2023-10-15
# ==============================================

# 基础配置
INSTALL_DIR="/root/VPN/MAIL"
CONFIG_FILE="/etc/postfix/main.cf"
DOVECOT_CONFIG="/etc/dovecot/dovecot.conf"
ROUNDCUBE_CONFIG="/var/www/roundcube/config/config.inc.php"

# 颜色定义
blue="\033[1;34m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
cyan="\033[1;36m"
reset="\033[0m"

# 函数：显示顶部边框
draw_top() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
}

# 函数：显示中间边框
draw_mid() {
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

# 函数：显示底部边框
draw_bottom() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 函数：彩色输出
cecho() {
  local color="$1"
  shift
  echo -e "${color}$*${reset}"
}

# 函数：显示标题
show_header() {
  clear
  draw_top
  printf "${blue}%*s${reset}\n" $(((${#1}+62)/2)) "$1"
  draw_mid
}

# 函数：DNS配置指南
dns_config() {
  show_header "🌐 DNS配置指南"
  
  cecho "$yellow" "请为您的域名添加以下DNS记录："
  cecho "$green" "1. A记录：@ → 您的服务器IP"
  cecho "$green" "2. A记录：mail → 您的服务器IP"
  cecho "$green" "3. MX记录：@ → mail.您的域名 (优先级10)"
  cecho "$green" "4. TXT记录：@ → v=spf1 mx ~all"
  cecho "$green" "5. TXT记录：_dmarc → v=DMARC1; p=none; rua=mailto:admin@您的域名"
  
  cecho "$yellow" "\n🔔 重要提示："
  cecho "$blue" "• 请将'您的域名'替换为实际域名"
  cecho "$blue" "• PTR记录需要联系服务器提供商设置"
  cecho "$blue" "• 测试命令: dig MX 您的域名 或 nslookup mail.您的域名"
  
  draw_bottom
  read -p "$(echo -e "💬 ${cyan}按回车键返回主菜单...${reset}")" dummy
}

# 函数：主域名设置
domain_setup() {
  show_header "📧 主域名配置"
  
  read -p "$(echo -e "${yellow}➤ 请输入您的邮件主域名 (如 example.com): ${reset}")" domain
  read -p "$(echo -e "${yellow}➤ 请输入邮件服务器主机名 (如 mail.example.com): ${reset}")" hostname
  
  # 配置Postfix
  postconf -e "myhostname = $hostname"
  postconf -e "mydomain = $domain"
  postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
  
  # 配置Dovecot
  echo "ssl_cert = </etc/letsencrypt/live/$hostname/fullchain.pem" >> $DOVECOT_CONFIG
  echo "ssl_key = </etc/letsencrypt/live/$hostname/privkey.pem" >> $DOVECOT_CONFIG
  
  cecho "$green" "\n✅ 主域名配置完成！"
  cecho "$blue" "Webmail访问地址: https://$hostname/roundcube"
  
  draw_bottom
  read -p "$(echo -e "💬 ${cyan}按回车键返回主菜单...${reset}")" dummy
}

# 函数：数据库配置
db_setup() {
  show_header "🗃️ 数据库配置"
  
  # 检查MySQL是否安装
  if ! command -v mysql &>/dev/null; then
    cecho "$red" "❌ MySQL未安装，正在自动安装..."
    apt update && apt install -y mysql-server
    mysql_secure_installation
  fi
  
  # 获取MySQL root密码
  while true; do
    read -p "$(echo -e "${yellow}➤ 请输入MySQL root密码: ${reset}")" -s rootpass
    echo
    if mysql -uroot -p"$rootpass" -e ";" 2>/dev/null; then
      break
    else
      cecho "$red" "✗ 密码错误，请重试"
    fi
  done
  
  DB_NAME="maildb_$(date +%s)"
  DB_USER="mailuser"
  DB_PASS=$(openssl rand -hex 12)
  
  # 创建数据库
  mysql -uroot -p"$rootpass" <<MYSQL_SCRIPT
CREATE DATABASE $DB_NAME DEFAULT CHARACTER SET utf8mb4;
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

  # 创建表结构
  mysql -uroot -p"$rootpass" $DB_NAME <<EOF
CREATE TABLE virtual_domains (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(50) NOT NULL UNIQUE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE virtual_users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  domain_id INT NOT NULL,
  email VARCHAR(100) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE virtual_aliases (
  id INT AUTO_INCREMENT PRIMARY KEY,
  domain_id INT NOT NULL,
  source VARCHAR(100) NOT NULL,
  destination VARCHAR(100) NOT NULL,
  FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO virtual_domains (name) VALUES ('$domain');
EOF

  cecho "$green" "\n✅ 数据库配置完成！"
  cecho "$blue" "数据库名: $DB_NAME"
  cecho "$blue" "用户名: $DB_USER"
  cecho "$blue" "密码: $DB_PASS"
  
  draw_bottom
  read -p "$(echo -e "💬 ${cyan}按回车键返回主菜单...${reset}")" dummy
}

# 函数：多域名管理
multi_domain() {
  show_header "🌍 多域名管理"
  
  cecho "$yellow" "当前主域名: $domain"
  cecho "$blue" "\n1. 添加子域名"
  cecho "$blue" "2. 设置全局收件"
  cecho "$blue" "3. 返回主菜单"
  
  read -p "$(echo -e "${yellow}➤ 请选择操作 [1-3]: ${reset}")" choice
  
  case $choice in
    1)
      read -p "$(echo -e "${yellow}➤ 请输入子域名 (如 sales.example.com): ${reset}")" subdomain
      mysql -uroot -p"$rootpass" $DB_NAME -e "INSERT INTO virtual_domains (name) VALUES ('$subdomain');"
      cecho "$green" "✅ 子域名 $subdomain 添加成功"
      cecho "$blue" "请为该子域名添加DNS MX记录指向 mail.$domain"
      ;;
    2)
      read -p "$(echo -e "${yellow}➤ 请输入全局收件邮箱 (如 catch-all@$domain): ${reset}")" catch_all
      mysql -uroot -p"$rootpass" $DB_NAME -e "
      INSERT INTO virtual_aliases (domain_id, source, destination)
      SELECT id, '@$domain', '$catch_all' FROM virtual_domains WHERE name='$domain';"
      cecho "$green" "✅ 全局收件设置成功！所有发送到 *@$domain 的邮件将转发到 $catch_all"
      ;;
    3)
      return ;;
    *)
      cecho "$red" "✗ 无效选择" ;;
  esac
  
  draw_bottom
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
  multi_domain
}

# 主菜单
main_menu() {
  while true; do
    show_header "邮件系统配置向导"
    
    cecho "$blue" "1. DNS配置指南"
    cecho "$blue" "2. 主域名设置"
    cecho "$blue" "3. 数据库配置"
    cecho "$blue" "4. 多域名管理"
    cecho "$blue" "5. 退出脚本"
    draw_mid
    
    read -p "$(echo -e "${yellow}➤ 请选择操作 [1-5]: ${reset}")" choice
    
    case $choice in
      1) dns_config ;;
      2) domain_setup ;;
      3) db_setup ;;
      4) multi_domain ;;
      5)
        show_header "感谢使用"
        cecho "$green" "邮件系统配置脚本已安全退出"
        draw_bottom
        exit 0 ;;
      *) 
        cecho "$red" "✗ 无效选择，请重新输入"
        sleep 1 ;;
    esac
  done
}

# 脚本入口
if [ "$(id -u)" != "0" ]; then
  cecho "$red" "⚠ 必须使用root用户运行此脚本！"
  exit 1
fi

main_menu
