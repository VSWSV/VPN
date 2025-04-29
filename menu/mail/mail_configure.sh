#!/bin/bash
# ==============================================
# 邮局服务器配置脚本 FINAL版（适配 Ubuntu 20.04）
# By VSWSV 定制，全中文提示，美化输出
# 功能：自动释放端口、配置Postfix+Dovecot+Roundcube、SSL、Apache、DNS指引
# ==============================================

# 颜色定义
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
reset="\033[0m"

# 美化分割线
function draw_line() {
    echo -e "${blue}================================================================================${reset}"
}

# 成功提示
function success() {
    echo -e "${green}[成功]${reset} $1"
}

# 警告提示
function warn() {
    echo -e "${yellow}[警告]${reset} $1"
}

# 错误提示
function error_exit() {
    echo -e "${red}[错误]${reset} $1"
    exit 1
}

# 检查端口是否被占用，如果占用则杀掉
function check_and_kill_port() {
    port=$1
    pid_info=$(lsof -i :${port} -t)
    if [[ -n "$pid_info" ]]; then
        pname=$(ps -p "$pid_info" -o comm=)
        warn "端口 ${port} 已被占用，进程名: ${pname} (PID: ${pid_info})"
        kill -9 "$pid_info" && success "已释放端口 ${port}（进程 $pname）"
    else
        success "端口 ${port} 空闲，可以使用。"
    fi
}

# 检查必要端口
function check_ports() {
    draw_line
    echo -e "${green}开始检查必要端口是否被占用...${reset}"
    for port in 25 587 143 993; do
        check_and_kill_port $port
    done
    draw_line
}

# 输入域名信息
function input_domain() {
    draw_line
    echo -e "${green}请输入基本域名信息${reset}"
    read -p "请输入主域名 (例如 vswsv.com): " DOMAIN
    [[ -z "$DOMAIN" ]] && error_exit "主域名不能为空！"
    read -p "请输入子域名前缀 (默认 mail): " SUB
    [[ -z "$SUB" ]] && SUB="mail"
    MAILDOMAIN="${SUB}.${DOMAIN}"
    success "设置的邮箱子域名为：${MAILDOMAIN}"
    draw_line
}

# 输入数据库信息
function input_db() {
    draw_line
    echo -e "${green}请输入 MariaDB 数据库信息${reset}"
    read -p "请输入数据库名 (默认 mailserver): " DBNAME
    [[ -z "$DBNAME" ]] && DBNAME="mailserver"
    read -p "请输入数据库用户名 (默认 mailuser): " DBUSER
    [[ -z "$DBUSER" ]] && DBUSER="mailuser"
    read -p "请输入数据库用户密码: " DBPASS
    [[ -z "$DBPASS" ]] && error_exit "数据库密码不能为空！"

    echo -e "${yellow}将测试连接 MariaDB...${reset}"
    read -p "请输入MariaDB root密码: " ROOTPASS
    mysql -uroot -p"$ROOTPASS" -e "quit" 2>/dev/null || error_exit "无法连接MariaDB root，请确认密码正确！"
    success "MariaDB连接正常。"
    draw_line
}

# 创建数据库和表
function setup_db() {
    draw_line
    echo -e "${green}正在创建数据库和表结构...${reset}"
    mysql -uroot -p"$ROOTPASS" <<EOF
CREATE DATABASE IF NOT EXISTS ${DBNAME} DEFAULT CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS '${DBUSER}'@'localhost' IDENTIFIED BY '${DBPASS}';
GRANT ALL PRIVILEGES ON ${DBNAME}.* TO '${DBUSER}'@'localhost';
FLUSH PRIVILEGES;
USE ${DBNAME};
CREATE TABLE IF NOT EXISTS domain (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    active TINYINT(1) DEFAULT 1
);
CREATE TABLE IF NOT EXISTS mailbox (
    id INT PRIMARY KEY AUTO_INCREMENT,
    domain_id INT,
    username VARCHAR(255) NOT NULL,
    password VARCHAR(255) NOT NULL,
    name VARCHAR(255),
    maildir VARCHAR(255) NOT NULL,
    active TINYINT(1) DEFAULT 1
);
CREATE TABLE IF NOT EXISTS alias (
    id INT PRIMARY KEY AUTO_INCREMENT,
    domain_id INT,
    source VARCHAR(255) NOT NULL,
    destination TEXT NOT NULL,
    active TINYINT(1) DEFAULT 1
);
EOF
    mysql -uroot -p"$ROOTPASS" -e "INSERT IGNORE INTO ${DBNAME}.domain (name) VALUES ('$DOMAIN');"
    success "数据库 ${DBNAME} 及相关表创建完成。"
    draw_line
}

# 配置Postfix主参数
function config_postfix() {
    draw_line
    echo -e "${green}正在配置Postfix主参数...${reset}"
    postconf -e "myhostname = $MAILDOMAIN"
    postconf -e "mydestination = localhost"
    postconf -e "virtual_mailbox_domains = mysql:/etc/postfix/mysql-virtual-domains.cf"
    postconf -e "virtual_mailbox_maps = mysql:/etc/postfix/mysql-virtual-mailboxes.cf"
    postconf -e "virtual_alias_maps = mysql:/etc/postfix/mysql-virtual-aliases.cf"
    postconf -e "virtual_transport = lmtp:unix:private/dovecot-lmtp"
    postconf -e "smtpd_sasl_auth_enable = yes"
    postconf -e "smtpd_tls_auth_only = yes"
    postconf -e "smtpd_tls_security_level = may"
    postconf -e "smtpd_tls_cert_file = /etc/letsencrypt/live/$MAILDOMAIN/fullchain.pem"
    postconf -e "smtpd_tls_key_file = /etc/letsencrypt/live/$MAILDOMAIN/privkey.pem"
    postconf -e "smtp_tls_security_level = may"
    postconf -e "smtpd_tls_loglevel = 1"
    postconf -e "smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache"
    success "Postfix主参数配置完成。"
    draw_line
}
# 配置Postfix查询MySQL
function config_postfix_mysql() {
    draw_line
    echo -e "${green}正在配置Postfix与MySQL集成...${reset}"
    mkdir -p /etc/postfix/sql
    cat >/etc/postfix/mysql-virtual-domains.cf <<EOF
user = ${DBUSER}
password = ${DBPASS}
hosts = 127.0.0.1
dbname = ${DBNAME}
query = SELECT 1 FROM domain WHERE name='%s' AND active = 1
EOF

    cat >/etc/postfix/mysql-virtual-mailboxes.cf <<EOF
user = ${DBUSER}
password = ${DBPASS}
hosts = 127.0.0.1
dbname = ${DBNAME}
query = SELECT 1 FROM mailbox WHERE username='%u' AND active = 1
EOF

    cat >/etc/postfix/mysql-virtual-aliases.cf <<EOF
user = ${DBUSER}
password = ${DBPASS}
hosts = 127.0.0.1
dbname = ${DBNAME}
query = SELECT destination FROM alias WHERE source='%s' AND active = 1
EOF

    success "Postfix MySQL 配置文件创建完成。"
    draw_line
}

# 配置Dovecot
function config_dovecot() {
    draw_line
    echo -e "${green}正在配置Dovecot主参数...${reset}"

    sed -i "s|^#mail_location =.*|mail_location = maildir:/var/mail/vhosts/%d/%n|" /etc/dovecot/conf.d/10-mail.conf

    sed -i "s/^!include auth-system.conf.ext/#!include auth-system.conf.ext/" /etc/dovecot/conf.d/10-auth.conf
    sed -i "s/^#!include auth-sql.conf.ext/!include auth-sql.conf.ext/" /etc/dovecot/conf.d/10-auth.conf

    mkdir -p /etc/dovecot/sql
    cat >/etc/dovecot/dovecot-sql.conf.ext <<EOF
driver = mysql
connect = host=127.0.0.1 dbname=${DBNAME} user=${DBUSER} password=${DBPASS}
default_pass_scheme = MD5-CRYPT
password_query = SELECT username AS user, password FROM mailbox WHERE username='%u' AND active = 1
user_query = SELECT maildir AS home, 5000 AS uid, 5000 AS gid FROM mailbox WHERE username='%u' AND active = 1
EOF

    mkdir -p /var/mail/vhosts/$DOMAIN
    groupadd -g 5000 vmail >/dev/null 2>&1 || true
    useradd -g vmail -u 5000 vmail -d /var/mail/vhosts >/dev/null 2>&1 || true
    chown -R vmail:vmail /var/mail/vhosts

    success "Dovecot配置完成。"
    draw_line
}

# 生成DKIM密钥
function setup_dkim() {
    draw_line
    echo -e "${green}正在生成DKIM密钥...${reset}"
    mkdir -p /etc/opendkim/keys/$DOMAIN
    opendkim-genkey -D /etc/opendkim/keys/$DOMAIN/ -d $DOMAIN -s default
    chown opendkim:opendkim /etc/opendkim/keys/$DOMAIN/default.private

    echo "default._domainkey.${DOMAIN} ${DOMAIN}:default:/etc/opendkim/keys/${DOMAIN}/default.private" >> /etc/opendkim/KeyTable
    echo "*@${DOMAIN} default._domainkey.${DOMAIN}" >> /etc/opendkim/SigningTable
    echo "127.0.0.1" >> /etc/opendkim/TrustedHosts
    echo "localhost" >> /etc/opendkim/TrustedHosts

    success "DKIM密钥生成成功。"
    draw_line
}

# 检查并申请SSL证书
function setup_ssl() {
    draw_line
    echo -e "${green}准备申请 Let's Encrypt 证书...${reset}"
    systemctl stop apache2
    certbot certonly --standalone -d $MAILDOMAIN --agree-tos --email admin@$DOMAIN --non-interactive
    if [[ $? -ne 0 ]]; then
        warn "SSL证书申请失败，降级为HTTP访问。"
        SSL_ENABLED=false
    else
        success "SSL证书申请成功。"
        SSL_ENABLED=true
    fi
    systemctl start apache2
    draw_line
}

# 配置Apache虚拟主机
function config_apache() {
    draw_line
    echo -e "${green}正在配置Apache虚拟主机...${reset}"
    mkdir -p /etc/apache2/sites-available

    if [[ $SSL_ENABLED == true ]]; then
        cat >/etc/apache2/sites-available/${MAILDOMAIN}.conf <<EOF
<VirtualHost *:443>
    ServerName ${MAILDOMAIN}
    DocumentRoot /var/lib/roundcube

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/${MAILDOMAIN}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${MAILDOMAIN}/privkey.pem

    <Directory /var/lib/roundcube>
        Options -Indexes
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
    else
        cat >/etc/apache2/sites-available/${MAILDOMAIN}.conf <<EOF
<VirtualHost *:80>
    ServerName ${MAILDOMAIN}
    DocumentRoot /var/lib/roundcube

    <Directory /var/lib/roundcube>
        Options -Indexes
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
    fi

    a2ensite ${MAILDOMAIN}.conf
    a2enmod ssl rewrite
    systemctl reload apache2
    success "Apache配置完成，绑定子域 ${MAILDOMAIN}"
    draw_line
}
# 配置Roundcube连接数据库
function config_roundcube() {
    draw_line
    echo -e "${green}正在配置Roundcube数据库连接信息...${reset}"
    if [ -f /etc/roundcube/config.inc.php ]; then
        sed -i "/\$config\['db_dsnw'\]/d" /etc/roundcube/config.inc.php
        echo "\$config['db_dsnw'] = 'mysqli://${DBUSER}:${DBPASS}@localhost/${DBNAME}';" >> /etc/roundcube/config.inc.php
        success "Roundcube数据库连接配置完成。"
    else
        warn "未找到Roundcube配置文件，跳过。"
    fi
    draw_line
}

# 输出DNS配置建议
function output_dns() {
    draw_line
    echo -e "${green}请根据以下信息配置您的DNS记录：${reset}"
    echo -e "${yellow}  - 类型: A   主机名: @       内容: [服务器公网IP]   TTL: 3600${reset}"
    echo -e "${yellow}  - 类型: A   主机名: $SUB    内容: [服务器公网IP]   TTL: 3600${reset}"
    echo -e "${yellow}  - 类型: MX  主机名: @       内容: $MAILDOMAIN (优先级10) TTL: 3600${reset}"
    echo -e "${yellow}  - 类型: TXT 主机名: @       内容: \"v=spf1 mx ~all\" TTL: 3600${reset}"
    if [[ -f /etc/opendkim/keys/${DOMAIN}/default.txt ]]; then
        DKIMTXT=$(grep -v '-----' /etc/opendkim/keys/${DOMAIN}/default.txt | sed ':a;N;$!ba;s/\n//g' | sed 's/ //g')
        echo -e "${yellow}  - 类型: TXT 主机名: default._domainkey.${DOMAIN} 内容: \"${DKIMTXT}\" TTL: 3600${reset}"
    else
        warn "未找到DKIM公钥，请手动检查。"
    fi
    echo -e "${yellow}  - 类型: TXT 主机名: _dmarc 内容: \"v=DMARC1; p=none; rua=mailto:postmaster@${DOMAIN}\" TTL: 3600${reset}"
    echo
    echo -e "${blue}注意：使用Cloudflare等平台时，请设置为【仅DNS】，关闭小云朵代理！${reset}"
    draw_line
}

# 脚本执行入口
function main() {
    draw_line
    echo -e "${green}🚀 欢迎使用 邮局服务器一键配置脚本 🚀${reset}"
    check_ports
    input_domain
    input_db
    setup_db
    config_postfix
    config_postfix_mysql
    config_dovecot
    setup_dkim
    setup_ssl
    config_apache
    config_roundcube
    output_dns
    echo -e "${green}🎉 邮局服务器配置完成！请重启Postfix、Dovecot和Apache服务。${reset}"
    draw_line
}

main


