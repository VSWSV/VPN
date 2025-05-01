#!/bin/bash
# ==============================================
# 邮件服务器一键配置脚本 (Postfix + Dovecot + OpenDKIM + Roundcube)
# 版本: 3.0
# 更新: 2023-11-20
# 支持: Ubuntu 20.04/22.04 | Debian 10/11
# 功能:
#   - SMTP (25/465/587) with TLS
#   - IMAP/POP3 (993/995) with SSL
#   - MySQL 集成
#   - OpenDKIM 签名
#   - Roundcube 网页邮件
# ==============================================

# ----------------------------
# ① 初始化设置
# ----------------------------
# 颜色定义
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
reset="\033[0m"

# 系统检测
OS=$(lsb_release -is)
CODENAME=$(lsb_release -cs)
IP=$(hostname -I | awk '{print $1}')

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${red}错误: 必须使用root用户运行此脚本${reset}"
  exit 1
fi

# ----------------------------
# ② 辅助函数
# ----------------------------
function line() {
  echo -e "${blue}================================================================================${reset}"
}

function success() {
  echo -e "${green}[✓]${reset} $1"
}

function warn() {
  echo -e "${yellow}[!]${reset} $1"
}

function fail() {
  echo -e "${red}[✗]${reset} $1"
  exit 1
}

function install_pkg() {
  if ! dpkg -l | grep -q "^ii  $1 "; then
    apt install -y $1 >/dev/null 2>&1 && success "安装 $1" || fail "安装 $1 失败"
  else
    success "$1 已安装"
  fi
}

# ----------------------------
# ③ 端口管理
# ----------------------------
function port_check() {
  line
  echo -e "${green}检查端口占用情况...${reset}"
  
  declare -A PORT_SERVICES=(
    ["25"]="Postfix"
    ["465"]="Postfix/SMTPS"
    ["587"]="Postfix/Submission"
    ["993"]="Dovecot/IMAPS"
    ["995"]="Dovecot/POP3S"
    ["143"]="Dovecot/IMAP"
    ["110"]="Dovecot/POP3"
  )

  for port in "${!PORT_SERVICES[@]}"; do
    if ss -tulnp | grep -q ":$port "; then
      pid=$(ss -tulnp | grep ":$port " | awk '{print $NF}' | cut -d= -f2 | cut -d, -f1)
      service_name=$(ps -p $pid -o comm= 2>/dev/null || echo "未知服务")
      warn "${PORT_SERVICES[$port]} 端口 $port 被 $service_name (PID: $pid) 占用"
      
      read -p "是否终止该进程? [y/N] " choice
      if [[ $choice =~ ^[Yy]$ ]]; then
        kill -9 $pid 2>/dev/null
        success "已终止进程 $pid"
      else
        fail "必须释放端口 $port 才能继续"
      fi
    else
      success "${PORT_SERVICES[$port]} 端口 $port 可用"
    fi
  done
}

# ----------------------------
# ④ 用户输入
# ----------------------------
function user_input() {
  line
  echo -e "${green}请输入配置信息${reset}"
  
  # 域名设置
  while true; do
    read -p "主域名 (如 example.com): " DOMAIN
    if [[ $DOMAIN =~ ^[a-zA-Z0-9.-]+$ ]]; then
      break
    else
      warn "域名格式无效"
    fi
  done
  
  read -p "邮件服务器子域名 [默认 mail]: " SUB
  SUB=${SUB:-mail}
  MAILDOMAIN="${SUB}.${DOMAIN}"
  
  # 数据库设置
  echo -e "\n${yellow}数据库配置${reset}"
  read -p "数据库名 [默认 maildb]: " DBNAME
  DBNAME=${DBNAME:-maildb}
  
  read -p "数据库用户 [默认 mailuser]: " DBUSER
  DBUSER=${DBUSER:-mailuser}
  
  while true; do
    read -s -p "数据库密码: " DBPASS
    echo
    if [ -n "$DBPASS" ]; then
      break
    else
      warn "密码不能为空"
    fi
  done
  
  # MariaDB root 密码
  while true; do
    read -s -p "MariaDB root 密码: " ROOTPASS
    echo
    if mysql -uroot -p"$ROOTPASS" -e "quit" 2>/dev/null; then
      break
    else
      warn "MariaDB root 密码错误"
    fi
  done
  
  # SSL 证书邮箱
  read -p "SSL 证书通知邮箱 (用于Let's Encrypt): " SSLEMAIL
  SSLEMAIL=${SSLEMAIL:-admin@$DOMAIN}
  
  success "配置信息收集完成"
}

# ----------------------------
# ⑤ 数据库配置
# ----------------------------
function setup_database() {
  line
  echo -e "${green}配置邮件数据库...${reset}"
  
  # 创建数据库和用户
  mysql -uroot -p"$ROOTPASS" <<EOF
CREATE DATABASE IF NOT EXISTS ${DBNAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DBUSER}'@'localhost' IDENTIFIED BY '${DBPASS}';
GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${DBUSER}'@'localhost';
FLUSH PRIVILEGES;
USE ${DBNAME};
CREATE TABLE IF NOT EXISTS domains (
  id INT AUTO_INCREMENT PRIMARY KEY,
  domain VARCHAR(255) NOT NULL UNIQUE,
  active BOOLEAN DEFAULT TRUE
);
CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  domain_id INT NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  active BOOLEAN DEFAULT TRUE,
  FOREIGN KEY (domain_id) REFERENCES domains(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS aliases (
  id INT AUTO_INCREMENT PRIMARY KEY,
  domain_id INT NOT NULL,
  source VARCHAR(255) NOT NULL,
  destination TEXT NOT NULL,
  active BOOLEAN DEFAULT TRUE,
  FOREIGN KEY (domain_id) REFERENCES domains(id) ON DELETE CASCADE
);
INSERT IGNORE INTO domains (domain) VALUES ('$DOMAIN');
EOF

  success "邮件数据库配置完成"
}

# ----------------------------
# ⑥ Postfix 配置
# ----------------------------
function setup_postfix() {
  line
  echo -e "${green}配置Postfix...${reset}"
  
  install_pkg postfix
  install_pkg postfix-mysql
  
  # 基本配置
  postconf -e "myhostname = $MAILDOMAIN"
  postconf -e "mydomain = $DOMAIN"
  postconf -e "myorigin = \$mydomain"
  postconf -e "mydestination = localhost"
  postconf -e "mynetworks = 127.0.0.0/8"
  postconf -e "inet_interfaces = all"
  postconf -e "home_mailbox = Maildir/"
  postconf -e "mailbox_command = "
  
  # MySQL 集成
  mkdir -p /etc/postfix/sql
  
  cat > /etc/postfix/sql/virtual_domains.cf <<EOF
user = $DBUSER
password = $DBPASS
hosts = 127.0.0.1
dbname = $DBNAME
query = SELECT 1 FROM domains WHERE domain='%s' AND active=1
EOF

  cat > /etc/postfix/sql/virtual_mailboxes.cf <<EOF
user = $DBUSER
password = $DBPASS
hosts = 127.0.0.1
dbname = $DBNAME
query = SELECT 1 FROM users WHERE email='%s' AND active=1
EOF

  cat > /etc/postfix/sql/virtual_aliases.cf <<EOF
user = $DBUSER
password = $DBPASS
hosts = 127.0.0.1
dbname = $DBNAME
query = SELECT destination FROM aliases WHERE source='%s' AND active=1
EOF

  postconf -e "virtual_mailbox_domains = mysql:/etc/postfix/sql/virtual_domains.cf"
  postconf -e "virtual_mailbox_maps = mysql:/etc/postfix/sql/virtual_mailboxes.cf"
  postconf -e "virtual_alias_maps = mysql:/etc/postfix/sql/virtual_aliases.cf"
  
  # 虚拟用户设置
  postconf -e "virtual_mailbox_base = /var/mail/vhosts"
  postconf -e "virtual_uid_maps = static:5000"
  postconf -e "virtual_gid_maps = static:5000"
  postconf -e "virtual_create_maildirsize = yes"
  
  # TLS 配置
  postconf -e "smtpd_tls_cert_file = /etc/letsencrypt/live/$MAILDOMAIN/fullchain.pem"
  postconf -e "smtpd_tls_key_file = /etc/letsencrypt/live/$MAILDOMAIN/privkey.pem"
  postconf -e "smtpd_tls_security_level = may"
  postconf -e "smtpd_tls_auth_only = yes"
  
  # SASL 认证
  postconf -e "smtpd_sasl_auth_enable = yes"
  postconf -e "smtpd_sasl_type = dovecot"
  postconf -e "smtpd_sasl_path = private/auth"
  postconf -e "smtpd_sasl_security_options = noanonymous"
  
  # 启用 Submission (587) 和 SMTPS (465)
  cat >> /etc/postfix/master.cf <<EOF
submission inet n - y - - smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
smtps inet n - y - - smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
EOF

  systemctl restart postfix
  success "Postfix 配置完成"
}

# ----------------------------
# ⑦ Dovecot 配置
# ----------------------------
function setup_dovecot() {
  line
  echo -e "${green}配置Dovecot...${reset}"
  
  install_pkg dovecot-core
  install_pkg dovecot-imapd
  install_pkg dovecot-pop3d
  install_pkg dovecot-mysql
  install_pkg dovecot-lmtpd
  
  # 基础配置
  sed -i 's/^#ssl =.*/ssl = required/' /etc/dovecot/conf.d/10-ssl.conf
  sed -i "s|^#ssl_cert =.*|ssl_cert = </etc/letsencrypt/live/$MAILDOMAIN/fullchain.pem|" /etc/dovecot/conf.d/10-ssl.conf
  sed -i "s|^#ssl_key =.*|ssl_key = </etc/letsencrypt/live/$MAILDOMAIN/privkey.pem|" /etc/dovecot/conf.d/10-ssl.conf
  
  # 认证配置
  echo "disable_plaintext_auth = no" > /etc/dovecot/conf.d/10-auth.conf
  echo "auth_mechanisms = plain login" >> /etc/dovecot/conf.d/10-auth.conf
  echo "!include auth-sql.conf.ext" >> /etc/dovecot/conf.d/10-auth.conf
  
  # SQL 认证
  cat > /etc/dovecot/conf.d/auth-sql.conf.ext <<EOF
passdb {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
userdb {
  driver = static
  args = uid=vmail gid=vmail home=/var/mail/vhosts/%d/%n
}
EOF

  cat > /etc/dovecot/dovecot-sql.conf.ext <<EOF
driver = mysql
connect = host=127.0.0.1 dbname=$DBNAME user=$DBUSER password=$DBPASS
default_pass_scheme = SHA512-CRYPT
password_query = SELECT email AS user, password FROM users WHERE email='%u' AND active=1
EOF

  # 邮箱存储
  mkdir -p /var/mail/vhosts/$DOMAIN
  groupadd -g 5000 vmail 2>/dev/null
  useradd -g vmail -u 5000 vmail -d /var/mail 2>/dev/null
  chown -R vmail:vmail /var/mail
  
  # 邮件位置
  sed -i 's|^#mail_location =.*|mail_location = maildir:/var/mail/vhosts/%d/%n|' /etc/dovecot/conf.d/10-mail.conf
  
  # 主服务配置
  cat > /etc/dovecot/conf.d/10-master.conf <<EOF
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0666
    user = postfix
    group = postfix
  }
}
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}
EOF

  systemctl restart dovecot
  success "Dovecot 配置完成"
}

# ----------------------------
# ⑧ OpenDKIM 配置
# ----------------------------
function setup_opendkim() {
  line
  echo -e "${green}配置OpenDKIM...${reset}"
  
  install_pkg opendkim
  install_pkg opendkim-tools
  
  mkdir -p /etc/opendkim/keys/$DOMAIN
  opendkim-genkey -D /etc/opendkim/keys/$DOMAIN/ -d $DOMAIN -s default
  chown -R opendkim:opendkim /etc/opendkim
  
  # 主配置文件
  cat > /etc/opendkim.conf <<EOF
Syslog          yes
UMask           002
Canonicalization relaxed/simple
Mode            sv
SubDomains      no
Socket          inet:12301@localhost
KeyTable        /etc/opendkim/KeyTable
SigningTable    /etc/opendkim/SigningTable
InternalHosts   /etc/opendkim/TrustedHosts
EOF

  # KeyTable
  echo "default._domainkey.$DOMAIN $DOMAIN:default:/etc/opendkim/keys/$DOMAIN/default.private" > /etc/opendkim/KeyTable

  # SigningTable
  echo "*@$DOMAIN default._domainkey.$DOMAIN" > /etc/opendkim/SigningTable

  # TrustedHosts
  cat > /etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
$DOMAIN
$MAILDOMAIN
EOF

  # 链接Postfix
  postconf -e "milter_default_action = accept"
  postconf -e "milter_protocol = 6"
  postconf -e "smtpd_milters = inet:localhost:12301"
  postconf -e "non_smtpd_milters = inet:localhost:12301"
  
  systemctl restart opendkim postfix
  success "OpenDKIM 配置完成"
}

# ----------------------------
# ⑨ SSL 证书
# ----------------------------
function setup_ssl() {
  line
  echo -e "${green}配置SSL证书...${reset}"
  
  install_pkg certbot
  
  # 临时停止占用80端口的服务
  systemctl stop apache2 nginx 2>/dev/null
  
  # 申请证书
  certbot certonly --standalone -d $MAILDOMAIN --agree-tos --email $SSLEMAIL --non-interactive
  
  # 重启服务
  systemctl start apache2 nginx 2>/dev/null
  
  # 检查证书
  if [ -f "/etc/letsencrypt/live/$MAILDOMAIN/fullchain.pem" ]; then
    success "SSL 证书已安装"
    # 设置自动续期
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook \"systemctl reload postfix dovecot\"") | crontab -
  else
    warn "SSL 证书获取失败，请手动检查"
  fi
}

# ----------------------------
# ⑩ Roundcube 配置
# ----------------------------
function setup_roundcube() {
  line
  echo -e "${green}配置Roundcube...${reset}"
  
  install_pkg roundcube
  install_pkg roundcube-core
  install_pkg roundcube-mysql
  install_pkg roundcube-plugins
  
  # 配置Apache
  cat > /etc/apache2/sites-available/roundcube.conf <<EOF
<VirtualHost *:80>
  ServerName $MAILDOMAIN
  Redirect permanent / https://$MAILDOMAIN/
</VirtualHost>

<VirtualHost *:443>
  ServerName $MAILDOMAIN
  DocumentRoot /var/lib/roundcube
  
  SSLEngine on
  SSLCertificateFile /etc/letsencrypt/live/$MAILDOMAIN/fullchain.pem
  SSLCertificateKeyFile /etc/letsencrypt/live/$MAILDOMAIN/privkey.pem
  
  <Directory /var/lib/roundcube>
    Options -Indexes
    AllowOverride All
    Require all granted
  </Directory>
  
  ErrorLog \${APACHE_LOG_DIR}/roundcube_error.log
  CustomLog \${APACHE_LOG_DIR}/roundcube_access.log combined
</VirtualHost>
EOF

  # 数据库配置
  mysql -uroot -p"$ROOTPASS" $DBNAME <<EOF
CREATE TABLE IF NOT EXISTS roundcube.contacts (
  contact_id int(10) UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id int(10) UNSIGNED NOT NULL,
  changed datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
  del tinyint(1) NOT NULL DEFAULT 0,
  name varchar(128) NOT NULL DEFAULT '',
  email text NOT NULL,
  PRIMARY KEY (contact_id),
  KEY user_id (user_id),
  KEY email (email(255))
ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS roundcube.identities (
  identity_id int(10) UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id int(10) UNSIGNED NOT NULL,
  standard tinyint(1) NOT NULL DEFAULT 0,
  name varchar(128) NOT NULL,
  organization varchar(128) NOT NULL DEFAULT '',
  email varchar(128) NOT NULL,
  reply-to varchar(128) NOT NULL DEFAULT '',
  bcc varchar(128) NOT NULL DEFAULT '',
  signature text NOT NULL,
  html_signature tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (identity_id),
  KEY user_id (user_id),
  KEY email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
EOF

  # 配置Roundcube
  cat > /etc/roundcube/config.inc.php <<EOF
<?php
\$config = array();
\$config['db_dsnw'] = 'mysql://${DBUSER}:${DBPASS}@localhost/${DBNAME}';
\$config['default_host'] = 'ssl://${MAILDOMAIN}';
\$config['default_port'] = 993;
\$config['smtp_server'] = 'tls://${MAILDOMAIN}';
\$config['smtp_port'] = 587;
\$config['smtp_user'] = '%u';
\$config['smtp_pass'] = '%p';
\$config['support_url'] = '';
\$config['product_name'] = '${DOMAIN} 邮件系统';
\$config['des_key'] = '$(openssl rand -base64 24)';
\$config['plugins'] = array('archive', 'zipdownload');
\$config['skin'] = 'elastic';
EOF

  a2ensite roundcube.conf
  a2enmod ssl rewrite
  systemctl restart apache2
  
  success "Roundcube 配置完成"
}

# ----------------------------
# ⑪ 防火墙配置
# ----------------------------
function setup_firewall() {
  line
  echo -e "${green}配置防火墙...${reset}"
  
  if command -v ufw >/dev/null; then
    ufw allow 22/tcp
    ufw allow 25/tcp
    ufw allow 465/tcp
    ufw allow 587/tcp
    ufw allow 993/tcp
    ufw allow 995/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw --force enable
    success "UFW 防火墙已配置"
  elif command -v firewall-cmd >/dev/null; then
    firewall-cmd --permanent --add-service={smtp,smtps,submission,imaps,pop3s,http,https}
    firewall-cmd --reload
    success "Firewalld 已配置"
  else
    warn "未找到支持的防火墙工具"
  fi
}

# ----------------------------
# ⑫ 测试验证
# ----------------------------
function verify_setup() {
  line
  echo -e "${green}验证邮件服务器配置...${reset}"
  
  # 测试SMTP
  echo -e "${blue}[测试SMTP连接]${reset}"
  if echo "quit" | openssl s_client -connect $MAILDOMAIN:587 -starttls smtp -brief 2>/dev/null | grep -q "220"; then
    success "SMTP (587) 连接正常"
  else
    fail "SMTP (587) 连接失败"
  fi
  
  # 测试IMAP
  echo -e "\n${blue}[测试IMAP连接]${reset}"
  if echo "a LOGOUT" | openssl s_client -connect $MAILDOMAIN:993 -quiet 2>/dev/null | grep -q "OK"; then
    success "IMAPS (993) 连接正常"
  else
    fail "IMAPS (993) 连接失败"
  fi
  
  # 测试DNS记录
  echo -e "\n${blue}[测试DNS记录]${reset}"
  if dig +short mx $DOMAIN | grep -q "$MAILDOMAIN"; then
    success "MX 记录已设置"
  else
    warn "MX 记录未找到 (请设置 MX 指向 $MAILDOMAIN)"
  fi
  
  # 测试DKIM
  echo -e "\n${blue}[测试DKIM记录]${reset}"
  if dig +short txt default._domainkey.$DOMAIN | grep -q "v=DKIM1"; then
    success "DKIM 记录已设置"
  else
    warn "DKIM 记录未找到 (请添加以下TXT记录):"
    cat /etc/opendkim/keys/$DOMAIN/default.txt
  fi
  
  # 测试SPF
  echo -e "\n${blue}[测试SPF记录]${reset}"
  if dig +short txt $DOMAIN | grep -q "v=spf1"; then
    success "SPF 记录已设置"
  else
    warn "SPF 记录未找到 (请添加 TXT 记录: \"v=spf1 mx ~all\")"
  fi
  
  # 测试DMARC
  echo -e "\n${blue}[测试DMARC记录]${reset}"
  if dig +short txt _dmarc.$DOMAIN | grep -q "v=DMARC1"; then
    success "DMARC 记录已设置"
  else
    warn "DMARC 记录未找到 (建议添加 TXT 记录: \"v=DMARC1; p=none; rua=mailto:postmaster@$DOMAIN\")"
  fi
  
  # 测试网页邮件
  echo -e "\n${blue}[测试网页邮件访问]${reset}"
  if curl -s -I "https://$MAILDOMAIN" | grep -q "200 OK"; then
    success "Roundcube 可正常访问: https://$MAILDOMAIN"
  else
    warn "Roundcube 访问异常 (请检查Apache配置)"
  fi
}

# ----------------------------
# ⑬ 显示配置摘要
# ----------------------------
function show_summary() {
  line
  echo -e "${green}邮件服务器配置完成！${reset}"
  echo -e "${blue}▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔${reset}"
  echo -e "${yellow}▪ 服务器IP   :${reset} $IP"
  echo -e "${yellow}▪ 邮件域名   :${reset} $MAILDOMAIN"
  echo -e "${yellow}▪ 数据库信息 :${reset}"
  echo -e "   - 数据库名: $DBNAME"
  echo -e "   - 用户名  : $DBUSER"
  echo -e "   - 密码    : $DBPASS"
  echo -e "${yellow}▪ 服务端口   :${reset}"
  echo -e "   - SMTP     : 25 (非加密), 587 (STARTTLS)"
  echo -e "   - SMTPS    : 465 (SSL)"
  echo -e "   - IMAP     : 143 (STARTTLS), 993 (SSL)"
  echo -e "   - POP3     : 110 (STARTTLS), 995 (SSL)"
  echo -e "${yellow}▪ 网页邮件   :${reset} https://$MAILDOMAIN"
  echo -e "${yellow}▪ DKIM密钥   :${reset}"
  cat /etc/opendkim/keys/$DOMAIN/default.txt 2>/dev/null || echo "未生成"
  echo -e "${blue}▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔${reset}"
  echo -e "${green}使用以下信息配置邮件客户端:${reset}"
  echo -e "▪ 接收服务器: $MAILDOMAIN (IMAP/POP3)"
  echo -e "▪ 发送服务器: $MAILDOMAIN (SMTP)"
  echo -e "▪ 用户名   : 你的完整邮箱地址 (如 user@$DOMAIN)"
  echo -e "▪ 密码     : 你的邮箱密码"
  line
}

# ----------------------------
# 🚀 主执行流程
# ----------------------------
function main() {
  # 更新系统
  line
  echo -e "${green}更新系统软件包...${reset}"
  apt update && apt upgrade -y
  
  # 执行配置步骤
  port_check
  user_input
  setup_database
  setup_postfix
  setup_dovecot
  setup_opendkim
  setup_ssl
  setup_roundcube
  setup_firewall
  verify_setup
  show_summary
  
  # 完成提示
  line
  echo -e "${green}🎉 邮件服务器配置完成！${reset}"
  echo -e "请确保已正确设置DNS记录 (MX, SPF, DKIM, DMARC)"
  echo -e "访问网页邮件: ${blue}https://$MAILDOMAIN${reset}"
}

# 执行主函数
main
