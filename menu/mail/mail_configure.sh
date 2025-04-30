#!/bin/bash
# ① 颜色定义
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
cyan="\033[1;36m"
orange="\033[38;5;214m"
reset="\033[0m"

# ② 分隔线函数
function line() {
  echo -e "${cyan}================================================================================${reset}"
}

# ③ 成功提示函数
function success() {
  echo -e "${green}[成功]${reset} $1"
}

# ④ 警告提示函数
function warn() {
  echo -e "${yellow}[警告]${reset} $1"
}

# ⑤ 错误提示函数
function fail_exit() {
  echo -e "${red}[错误]${reset} $1"
  exit 1
}
# ⑥ 检查并逐个释放端口
function check_and_release_ports() {
  line
  echo -e "${green}检查必要端口是否被占用...${reset}"
  PORTS=(25 80 465 587 143 993 110 995)
  for PORT in "${PORTS[@]}"; do
    LISTEN_INFO=$(ss -tunlp | grep ":$PORT ")
    if [[ -n "$LISTEN_INFO" ]]; then
      PID=$(echo "$LISTEN_INFO" | grep -oP 'pid=\K[0-9]+' | head -n1)
      PROC=$(ps -p $PID -o comm= 2>/dev/null)
      if [[ -n "$PID" ]]; then
        echo -e "${yellow}[警告] 端口 $PORT 被占用，进程名: $PROC (PID: $PID)${reset}"
        kill -9 $PID >/dev/null 2>&1 && echo -e "${green}[成功] 已释放端口 $PORT（进程 $PROC）${reset}"
      else
        warn "端口 $PORT 占用进程PID解析失败"
      fi
    else
      echo -e "${green}[成功] 端口 $PORT 空闲，可以使用。${reset}"
    fi
  done
}

# ⑦ 输入基础域名
function get_basic_info() {
  line
  read -p "请输入主域名（例如 google.com）: " DOMAIN
  [[ -z "$DOMAIN" ]] && fail_exit "主域名不能为空"
  read -p "请输入子域名前缀（默认 mail）: " SUB
  [[ -z "$SUB" ]] && SUB="mail"
  MAILDOMAIN="${SUB}.${DOMAIN}"
  success "邮箱域名为：$MAILDOMAIN"
}

# ⑧ 输入数据库信息
function input_db_info() {
  line
  read -p "数据库名称（默认 mail）: " DBNAME
  [[ -z "$DBNAME" ]] && DBNAME="mail"
  read -p "数据库用户名（默认 mail）: " DBUSER
  [[ -z "$DBUSER" ]] && DBUSER="mail"
  read -p "数据库密码（必填）: " DBPASS
  [[ -z "$DBPASS" ]] && fail_exit "数据库密码不能为空"
  read -p "请输入 MariaDB root 密码： " ROOTPASS
  mysql -uroot -p"$ROOTPASS" -e "quit" 2>/dev/null || fail_exit "无法连接数据库 root 用户"
  success "数据库连接成功"
}

# ⑨ 创建数据库和表结构
function setup_mail_db() {
  line
  mysql -uroot -p"$ROOTPASS" <<EOF
CREATE DATABASE IF NOT EXISTS ${DBNAME} DEFAULT CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS '${DBUSER}'@'localhost' IDENTIFIED BY '${DBPASS}';
GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${DBUSER}'@'localhost';
FLUSH PRIVILEGES;
USE ${DBNAME};
CREATE TABLE IF NOT EXISTS domain (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  active TINYINT(1) DEFAULT 1
);
CREATE TABLE IF NOT EXISTS mailbox (
  id INT AUTO_INCREMENT PRIMARY KEY,
  domain_id INT,
  username VARCHAR(255) NOT NULL,
  password VARCHAR(255) NOT NULL,
  name VARCHAR(255),
  maildir VARCHAR(255) NOT NULL,
  active TINYINT(1) DEFAULT 1
);
CREATE TABLE IF NOT EXISTS alias (
  id INT AUTO_INCREMENT PRIMARY KEY,
  domain_id INT,
  source VARCHAR(255) NOT NULL,
  destination TEXT NOT NULL,
  active TINYINT(1) DEFAULT 1
);
EOF
  mysql -uroot -p"$ROOTPASS" -e "INSERT IGNORE INTO ${DBNAME}.domain (name) VALUES ('$DOMAIN');"
  success "数据库 $DBNAME 创建完成"
}
# ⑩ 配置 Postfix 主参数
function config_postfix_main() {
  line
  postconf -e "myhostname = $MAILDOMAIN"
  postconf -e "mydomain = $DOMAIN"
  postconf -e "myorigin = /etc/mailname"
  postconf -e "mydestination = localhost"
  postconf -e "relay_domains ="
  postconf -e "home_mailbox = Maildir/"
  postconf -e "virtual_transport = lmtp:unix:private/dovecot-lmtp"
  postconf -e "mynetworks = 127.0.0.0/8"
  echo "$DOMAIN" > /etc/mailname
  success "Postfix 主参数配置完成"
}

# ⑪ 配置 Postfix MySQL 集成
function config_postfix_mysql() {
  line
  mkdir -p /etc/postfix/sql
  cat >/etc/postfix/sql/virtual_mailbox_domains.cf <<EOF
user = $DBUSER
password = $DBPASS
hosts = 127.0.0.1
dbname = $DBNAME
query = SELECT 1 FROM domain WHERE name='%s' AND active = 1
EOF

  cat >/etc/postfix/sql/virtual_mailbox_maps.cf <<EOF
user = $DBUSER
password = $DBPASS
hosts = 127.0.0.1
dbname = $DBNAME
query = SELECT 1 FROM mailbox WHERE username='%s' AND active = 1
EOF

  cat >/etc/postfix/sql/virtual_alias_maps.cf <<EOF
user = $DBUSER
password = $DBPASS
hosts = 127.0.0.1
dbname = $DBNAME
query = SELECT destination FROM alias WHERE source='%s' AND active = 1
EOF

  postconf -e "virtual_mailbox_domains = mysql:/etc/postfix/sql/virtual_mailbox_domains.cf"
  postconf -e "virtual_mailbox_maps = mysql:/etc/postfix/sql/virtual_mailbox_maps.cf"
  postconf -e "virtual_alias_maps = mysql:/etc/postfix/sql/virtual_alias_maps.cf"
  success "Postfix MySQL 集成配置完成"
}

# ⑫ 开启 Postfix 所有相关端口监听
function config_postfix_ports() {
  line
  MASTER_CF="/etc/postfix/master.cf"

  if ! grep -q "^smtps " $MASTER_CF; then
cat >>$MASTER_CF <<EOF

smtps     inet  n       -       y       -       -       smtpd
  -o syslog_name=postfix/smtps
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_tls_cert_file=/etc/letsencrypt/live/$MAILDOMAIN/fullchain.pem
  -o smtpd_tls_key_file=/etc/letsencrypt/live/$MAILDOMAIN/privkey.pem
EOF
  fi

  if ! grep -q "^submission " $MASTER_CF; then
cat >>$MASTER_CF <<EOF

submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
  -o smtpd_tls_cert_file=/etc/letsencrypt/live/$MAILDOMAIN/fullchain.pem
  -o smtpd_tls_key_file=/etc/letsencrypt/live/$MAILDOMAIN/privkey.pem
EOF
  fi

  # 主配置中设置 Postfix 与 Dovecot 的认证对接和 TLS 证书位置
  postconf -e "smtpd_tls_cert_file = /etc/letsencrypt/live/$MAILDOMAIN/fullchain.pem"
  postconf -e "smtpd_tls_key_file = /etc/letsencrypt/live/$MAILDOMAIN/privkey.pem"
  postconf -e "smtpd_tls_security_level = may"
  postconf -e "smtpd_tls_auth_only = yes"
  postconf -e "smtpd_sasl_auth_enable = yes"

  # 新增必要的虚拟用户目录参数
  postconf -e "virtual_mailbox_base = /var/mail/vhosts"
  postconf -e "virtual_uid_maps = static:5000"
  postconf -e "virtual_gid_maps = static:5000"

  success "Postfix 已启用 25/465/587 端口监听与认证配置"
}

# ⑬ 配置 Dovecot 所有端口协议支持
function config_dovecot() {
  line
  sed -i 's/^.*protocols =.*/protocols = imap pop3 lmtp/' /etc/dovecot/dovecot.conf
  sed -i 's/^.*ssl = .*/ssl = required/' /etc/dovecot/conf.d/10-ssl.conf
  sed -i "s|^.*ssl_cert =.*|ssl_cert = </etc/letsencrypt/live/$MAILDOMAIN/fullchain.pem|" /etc/dovecot/conf.d/10-ssl.conf
  sed -i "s|^.*ssl_key =.*|ssl_key = </etc/letsencrypt/live/$MAILDOMAIN/privkey.pem|" /etc/dovecot/conf.d/10-ssl.conf

  # 启用 SQL 认证，禁用系统认证
  sed -i 's/^!include auth-system.conf.ext/#!include auth-system.conf.ext/' /etc/dovecot/conf.d/10-auth.conf
  sed -i 's/^#!include auth-sql.conf.ext/!include auth-sql.conf.ext/' /etc/dovecot/conf.d/10-auth.conf

  # 设置 mail_location
  sed -i 's|^.*mail_location =.*|mail_location = maildir:/var/mail/vhosts/%d/%n|' /etc/dovecot/conf.d/10-mail.conf

  success "Dovecot IMAP/POP3/SSL 协议及路径配置完成"
}


# ⑮ 配置 Dovecot SQL 登录
function config_dovecot_sql() {
  line
  mkdir -p /etc/dovecot/sql
  cat >/etc/dovecot/dovecot-sql.conf.ext <<EOF
driver = mysql
connect = host=127.0.0.1 dbname=${DBNAME} user=${DBUSER} password=${DBPASS}
default_pass_scheme = MD5-CRYPT
password_query = SELECT username AS user, password FROM mailbox WHERE username='%u' AND active = 1
user_query = SELECT maildir AS home, 5000 AS uid, 5000 AS gid FROM mailbox WHERE username='%u' AND active = 1
EOF
  success "Dovecot SQL认证配置完成"
}

# ⑯ 生成 DKIM 密钥
function setup_dkim() {
  line
  mkdir -p /etc/opendkim/keys/$DOMAIN
  opendkim-genkey -D /etc/opendkim/keys/$DOMAIN/ -d $DOMAIN -s default
  chown -R opendkim:opendkim /etc/opendkim
  success "DKIM密钥生成成功"
}

# ⑰ 配置 opendkim.conf 与 postfix 配合项
function config_opendkim() {
  line
  cat >/etc/opendkim.conf <<EOF
Syslog          yes
UMask           002
Canonicalization    relaxed/simple
Mode            sv
SubDomains      no
Socket          inet:12301@localhost
KeyTable        /etc/opendkim/KeyTable
SigningTable    /etc/opendkim/SigningTable
InternalHosts   /etc/opendkim/TrustedHosts
EOF

  cat >/etc/opendkim/KeyTable <<EOF
default._domainkey.$DOMAIN $DOMAIN:default:/etc/opendkim/keys/$DOMAIN/default.private
EOF

  cat >/etc/opendkim/SigningTable <<EOF
*@${DOMAIN} default._domainkey.${DOMAIN}
EOF

  cat >/etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
$DOMAIN
EOF

  postconf -e "milter_default_action = accept"
  postconf -e "milter_protocol = 6"
  postconf -e "smtpd_milters = inet:localhost:12301"
  postconf -e "non_smtpd_milters = inet:localhost:12301"
  success "opendkim配置完成并与Postfix关联"
}
# ⑱ 申请 SSL 证书（自动关闭 Apache，防止端口冲突）
function setup_ssl() {
  line
  command -v certbot >/dev/null 2>&1 || apt install -y certbot

  read -p "请输入申请SSL证书使用的邮箱地址（如 admin@$DOMAIN）: " SSLEMAIL

  echo -e "${yellow}❗临时关闭 Apache 以释放 80 端口...${reset}"
  systemctl stop apache2

  CERTBOT_LOG="/tmp/certbot.log"
  certbot certonly --standalone -d "$MAILDOMAIN" --agree-tos --email "$SSLEMAIL" --non-interactive | tee "$CERTBOT_LOG"

  systemctl start apache2

  if [[ -f "/etc/letsencrypt/live/$MAILDOMAIN/fullchain.pem" ]]; then
    if grep -q "Certificate not yet due for renewal" "$CERTBOT_LOG"; then
      echo -e "${yellow}💡证书仍在有效期内，无需重新签发${reset}"
    else
      echo -e "${green}[成功] SSL证书申请成功${reset}"
    fi
  else
    echo -e "${red}[错误] 证书申请失败，请检查域名解析和端口占用${reset}"
    exit 1
  fi

  rm -f "$CERTBOT_LOG"
}
# ⑲ 配置 Apache 虚拟主机
function config_apache() {
  line
  local webroot="/var/www/html/roundcube"

  mkdir -p "$webroot"

  cat >/etc/apache2/sites-available/$MAILDOMAIN.conf <<EOF
<VirtualHost *:80>
  ServerName $MAILDOMAIN
  DocumentRoot $webroot

  <Directory $webroot>
    Options -Indexes
    AllowOverride All
    Require all granted
  </Directory>

  DirectoryIndex index.php index.html
</VirtualHost>

<VirtualHost *:443>
  ServerName $MAILDOMAIN
  DocumentRoot $webroot

  <Directory $webroot>
    Options -Indexes
    AllowOverride All
    Require all granted
  </Directory>

  DirectoryIndex index.php index.html

  SSLEngine on
  SSLCertificateFile /etc/letsencrypt/live/$MAILDOMAIN/fullchain.pem
  SSLCertificateKeyFile /etc/letsencrypt/live/$MAILDOMAIN/privkey.pem
</VirtualHost>
EOF

  a2enmod ssl rewrite php7.4 >/dev/null 2>&1 || a2enmod php8.1 >/dev/null 2>&1
  a2ensite $MAILDOMAIN.conf
  systemctl reload apache2
  success "Apache 虚拟主机配置完成"
}
# ⑳ 自动写入 Roundcube 数据库配置（最多3次重新检测）
function config_roundcube_db() {
  line
  echo -n "尝试检测 Roundcube 配置路径..."
  RC_PATH=$(find / -type f -name "config.inc.php" 2>/dev/null | grep roundcube | head -n1)

  SERVER_IP=$(hostname -I | awk '{print $1}')

  if [[ -z "$RC_PATH" ]]; then
    echo -e "${yellow}未找到 Roundcube 配置文件${reset}"
    echo -e "${yellow}[提示] 你可能尚未完成 Roundcube 安装。请访问以下地址进行网页安装：${reset}"
    echo -e "${cyan}http://${SERVER_IP}/roundcube/installer/${reset}"
  fi

  # 最多尝试3次等待用户安装后刷新检测
  try=1
  while [[ -z "$RC_PATH" && $try -le 3 ]]; do
    echo
    read -p "（第 ${try}/3 次）若你已完成网页安装，请按回车重新检测配置路径..." temp
    echo -n "重新检测配置文件..."
    RC_PATH=$(find / -type f -name "config.inc.php" 2>/dev/null | grep roundcube | head -n1)
    if [[ -z "$RC_PATH" ]]; then
      echo -e "${red}未找到${reset}"
    else
      echo -e "${green}已找到：$RC_PATH${reset}"
    fi
    try=$((try+1))
  done

  if [[ -z "$RC_PATH" ]]; then
    echo -e "${red}仍未找到 config.inc.php，配置写入已跳过${reset}"
    return
  fi

  if [[ -f "$RC_PATH" ]]; then
    sed -i "s#^\(\$config\['db_dsnw'\] = \).*#\1'mysql://${DBUSER}:${DBPASS}@localhost/${DBNAME}';#" "$RC_PATH"
    echo -e "${green}[成功]${reset} 已写入 Roundcube 配置文件：${cyan}$RC_PATH${reset}"
  else
    echo -e "${red}[错误] Roundcube 配置文件不可写，请检查权限${reset}"
  fi
}
# ㉒ 输出 DNS 配置建议（A/MX/TXT/SPF/DKIM/DMARC）
function output_dns() {
  line
  SERVER_IP=$(curl -s https://api.ipify.org)
  echo -e "${green}请根据以下信息配置 DNS 记录：${reset}"
  echo -e "${yellow}  - 类型: A    主机名: @         内容: ${SERVER_IP}         TTL: 3600${reset}"
  echo -e "${yellow}  - 类型: A    主机名: mail      内容: ${SERVER_IP}         TTL: 3600${reset}"
  echo -e "${yellow}  - 类型: MX   主机名: @         内容: mail.${DOMAIN} (优先级10) TTL: 3600${reset}"
  echo -e "${yellow}  - 类型: TXT  主机名: @         内容: \"v=spf1 mx ~all\"       TTL: 3600${reset}"

  DKIMFILE="/etc/opendkim/keys/${DOMAIN}/default.txt"
  if [[ -f "$DKIMFILE" ]]; then
    DKIMTXT=$(awk '/p=/{gsub(/"/, "", $0); print $0}' "$DKIMFILE" | tr -d '\n' | sed 's/.*p=//')
    if [[ -n "$DKIMTXT" ]]; then
      echo -e "${yellow}  - 类型: TXT  主机名: default._domainkey 内容: \"v=DKIM1; k=rsa; p=${DKIMTXT}\" TTL: 3600${reset}"
    else
      warn "DKIM 公钥为空，请检查 $DKIMFILE 文件内容"
    fi
  else
    warn "未找到 DKIM 公钥文件"
  fi

  echo -e "${yellow}  - 类型: TXT  主机名: _dmarc    内容: \"v=DMARC1; p=none; rua=mailto:postmaster@${DOMAIN}\" TTL: 3600${reset}"
  echo
  echo -e "${cyan}注意：Cloudflare用户请关闭代理（仅DNS），确保邮件正常。${reset}"
  line
}

# ㉓ 重启服务并检查监听状态
function restart_services_and_check_ports() {
  line
  echo -e "${green}重启所有服务...${reset}"
  systemctl restart postfix
  systemctl restart dovecot
  systemctl reload apache2
  sleep 1
  echo -e "${green}检测端口监听状态：${reset}"
  ss -tunlp | grep -E ':25|:465|:587|:110|:995|:143|:993' || warn "未监听任何关键端口"
}

# ㉔ 主函数执行 main()
function main() {
  check_and_release_ports
  get_basic_info
  input_db_info
  setup_mail_db
  config_postfix_main
  config_postfix_mysql
  config_postfix_ports
  config_dovecot
  setup_maildir
  config_dovecot_sql
  setup_dkim
  config_opendkim
  setup_ssl
  config_apache
  config_roundcube_db
  output_dns
  restart_services_and_check_ports
  echo -e "${green}🎉 邮局系统配置完成！请通过 Roundcube 登录测试。${reset}"
}

main
