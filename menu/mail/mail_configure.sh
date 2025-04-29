#!/bin/bash
# 邮局服务器配置脚本
# 自动配置 Postfix(SMTP)、Dovecot(IMAP/POP3)、MariaDB(邮箱账户)、
# 申请 Let's Encrypt 证书或使用已有证书，配置 Apache+Roundcube Webmail
# 美化提示，交互式询问

# 终端颜色定义
GREEN="\033[1;32m"
BLUE="\033[1;34m"
RED="\033[1;31m"
NC="\033[0m"

info()    { echo -e "${BLUE}==> $1${NC}"; }
success() { echo -e "${GREEN}==> $1${NC}"; }
error()   { echo -e "${RED}==> $1${NC}"; }

echo "============================= 邮局服务器配置脚本 ============================="
echo

# 1. 获取域名和子域
read -p "请输入邮箱服务器主域名（例如 example.com）: " domain
while [[ -z "$domain" ]]; do
    echo "域名不能为空，请重新输入。"
    read -p "请输入邮箱服务器主域名（例如 example.com）: " domain
done
read -p "请输入邮件子域名（默认 mail）: " subdomain
subdomain=${subdomain:-mail}
full_domain="${subdomain}.${domain}"
info "邮件子域名为：${full_domain}"

# 2. 配置 MariaDB (数据库)
read -p "请输入 MariaDB 数据库名（默认 mailserver）: " dbname
dbname=${dbname:-mailserver}
read -p "请输入 MariaDB 用户名（默认 mailuser）: " dbuser
dbuser=${dbuser:-mailuser}
echo -n "请输入 MariaDB 用户密码: "
read -s dbpass
echo

# 创建数据库和用户
info "正在创建数据库 ${dbname} 以及用户 ${dbuser}..."
sudo mysql -e "CREATE DATABASE IF NOT EXISTS \`${dbname}\`;"
sudo mysql -e "CREATE USER IF NOT EXISTS '${dbuser}'@'localhost' IDENTIFIED BY '$dbpass';"
sudo mysql -e "GRANT ALL PRIVILEGES ON \`${dbname}\`.* TO '${dbuser}'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"
success "数据库 ${dbname} 和用户 ${dbuser} 已创建。"

# 创建邮件虚拟域名和邮箱表
info "正在创建邮箱所需的数据库表结构..."
sudo mysql $dbname <<EOF
CREATE TABLE IF NOT EXISTS domain (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(50) NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1
);
CREATE TABLE IF NOT EXISTS mailbox (
    id INT PRIMARY KEY AUTO_INCREMENT,
    domain_id INT NOT NULL,
    username VARCHAR(50) NOT NULL,
    password VARCHAR(128) NOT NULL,
    name VARCHAR(100) NOT NULL,
    maildir VARCHAR(255) NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    FOREIGN KEY (domain_id) REFERENCES domain(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS alias (
    id INT PRIMARY KEY AUTO_INCREMENT,
    domain_id INT NOT NULL,
    source VARCHAR(100) NOT NULL,
    destination TEXT NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    FOREIGN KEY (domain_id) REFERENCES domain(id) ON DELETE CASCADE
);
EOF
success "数据库表创建完成。"

# 插入主域到 domain 表
sudo mysql $dbname -e "INSERT IGNORE INTO domain (name) VALUES ('$domain');"
domain_id=$(sudo mysql -N -s $dbname -e "SELECT id FROM domain WHERE name='$domain';")

# 创建 maildir 基础目录和用户
info "创建邮件存储目录并设置权限..."
sudo groupadd -g 5000 vmail >/dev/null 2>&1 || true
sudo useradd -g vmail -u 5000 vmail -d /var/mail >/dev/null 2>&1 || true
sudo mkdir -p /var/mail/vhosts/$domain
sudo chown -R vmail:vmail /var/mail/vhosts

# 3. 配置 Postfix
info "配置 Postfix..."
sudo postconf -e "myhostname = ${full_domain}"
sudo postconf -e "mydestination = ${full_domain}, localhost.${domain}, localhost, ${domain}"
sudo postconf -e "virtual_minimum_uid = 1000"
sudo postconf -e "virtual_mailbox_base = /var/mail/vhosts"

# 写入 Postfix MySQL 配置文件
sudo mkdir -p /etc/postfix/sql
sudo tee /etc/postfix/sql/mysql-virtual_domains.cf > /dev/null <<EOF
user = $dbuser
password = $dbpass
hosts = 127.0.0.1
dbname = $dbname
query = SELECT name FROM domain WHERE name='%s' AND active = 1
EOF

sudo tee /etc/postfix/sql/mysql-mailbox.cf > /dev/null <<EOF
user = $dbuser
password = $dbpass
hosts = 127.0.0.1
dbname = $dbname
query = SELECT maildir FROM mailbox INNER JOIN domain ON mailbox.domain_id = domain.id WHERE domain.name='%d' AND username='%u' AND mailbox.active = 1
EOF

sudo tee /etc/postfix/sql/mysql-aliases.cf > /dev/null <<EOF
user = $dbuser
password = $dbpass
hosts = 127.0.0.1
dbname = $dbname
query = SELECT destination FROM alias INNER JOIN domain ON alias.domain_id = domain.id WHERE domain.name='%d' AND source='%s' AND alias.active = 1
EOF

sudo postconf -e "virtual_mailbox_domains = mysql:/etc/postfix/sql/mysql-virtual_domains.cf"
sudo postconf -e "virtual_mailbox_maps = mysql:/etc/postfix/sql/mysql-mailbox.cf"
sudo postconf -e "virtual_alias_maps = mysql:/etc/postfix/sql/mysql-aliases.cf"
success "Postfix 已配置完成。"

# 4. 配置 Dovecot
info "配置 Dovecot..."
sudo tee /etc/dovecot/conf.d/10-mail.conf > /dev/null <<EOF
mail_location = maildir:/var/mail/vhosts/%d/%n
namespace inbox {
  inbox = yes
}
EOF

sudo tee /etc/dovecot/conf.d/auth-sql.conf.ext > /dev/null <<EOF
driver = mysql
connect = host=127.0.0.1 dbname=$dbname user=$dbuser password=$dbpass
default_pass_scheme = MD5-CRYPT
password_query = SELECT username AS user, password FROM mailbox INNER JOIN domain ON mailbox.domain_id=domain.id WHERE domain.name='%d' AND username='%u' AND active = 1
user_query = SELECT maildir AS home, 5000 AS uid, 5000 AS gid FROM mailbox INNER JOIN domain ON mailbox.domain_id=domain.id WHERE domain.name='%d' AND username='%u' AND active = 1
EOF

# 启用 SQL 认证
sudo sed -i 's/!include auth-sql.conf.ext/!include auth-sql.conf.ext/' /etc/dovecot/conf.d/10-auth.conf

# 协议设置
sudo sed -i 's/^protocols = .*/protocols = imap pop3 lmtp/' /etc/dovecot/dovecot.conf
success "Dovecot 已配置完成。"

# 5. 生成 DKIM 密钥 (OpenDKIM)
info "生成并配置 DKIM 密钥..."
sudo mkdir -p /etc/opendkim/keys/$domain
sudo opendkim-genkey -s default -d $domain -D /etc/opendkim/keys/$domain
sudo chown opendkim:opendkim /etc/opendkim/keys/$domain/default.private
sudo mkdir -p /etc/opendkim
echo "default._domainkey.$domain $domain:default:/etc/opendkim/keys/$domain/default.private" | sudo tee -a /etc/opendkim/KeyTable
echo "*@${domain} default._domainkey.$domain" | sudo tee -a /etc/opendkim/SigningTable
echo "127.0.0.1" | sudo tee -a /etc/opendkim/TrustedHosts
echo "localhost" | sudo tee -a /etc/opendkim/TrustedHosts
sudo sed -i 's/^#Socket/Socket inet:8891@localhost/' /etc/opendkim.conf
success "DKIM 密钥生成完成，公钥已保存在 /etc/opendkim/keys/$domain/default.txt。"

# 6. SSL/TLS 证书 (Let's Encrypt 或 手动)
read -p "是否使用 Let's Encrypt 自动申请证书？(Y/N): " use_le
if [[ $use_le =~ ^[Yy] ]]; then
    read -p "请输入您的邮箱，用于注册 Let's Encrypt（例如 admin@example.com）: " le_email
    info "正在申请 Let's Encrypt 证书..."
    sudo certbot certonly --standalone -d $full_domain --non-interactive --agree-tos -m $le_email
    cert_path="/etc/letsencrypt/live/$full_domain"
else
    read -p "请输入现有 fullchain.pem 证书路径: " cert_path_input
    read -p "请输入现有 privkey.pem 私钥路径: " key_path_input
    cert_path=$(dirname $cert_path_input)
    sudo mkdir -p $cert_path
    sudo cp $cert_path_input $cert_path/fullchain.pem
    sudo cp $key_path_input $cert_path/privkey.pem
fi

# 7. 配置 Apache2 和 Roundcube
info "安装并配置 Apache2 和 Roundcube Webmail..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y roundcube

# 检查并处理现有 Roundcube 配置
if [ -f /etc/roundcube/config.inc.php ]; then
    info "检测到已安装的 Roundcube 配置文件：/etc/roundcube/config.inc.php"
    grep "db_dsnw" /etc/roundcube/config.inc.php
    read -p "是否删除并重新安装 Roundcube？(Y/N): " rc_reinstall
    if [[ $rc_reinstall =~ ^[Yy] ]]; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y roundcube
        sudo rm -rf /etc/roundcube /var/lib/roundcube
        success "已删除旧的 Roundcube 安装"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y roundcube
        success "Roundcube 重新安装完成"
    else
        info "保留现有 Roundcube 配置"
    fi
fi

# 配置 Apache 虚拟主机
sudo tee /etc/apache2/sites-available/${full_domain}.conf > /dev/null <<EOF
<VirtualHost *:80>
    ServerName ${full_domain}
    Redirect "/" "https://${full_domain}/"
</VirtualHost>

<VirtualHost *:443>
    ServerName ${full_domain}
    DocumentRoot /usr/share/roundcube

    ErrorLog \${APACHE_LOG_DIR}/${full_domain}-error.log
    CustomLog \${APACHE_LOG_DIR}/${full_domain}-access.log combined

    SSLEngine on
    SSLCertificateFile $cert_path/fullchain.pem
    SSLCertificateKeyFile $cert_path/privkey.pem

    <Directory /usr/share/roundcube>
        Options -Indexes
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

sudo a2ensite ${full_domain}.conf
sudo a2enmod ssl rewrite
sudo systemctl reload apache2
success "Apache2 和 Roundcube 配置完成。"

# 8. 输出 DNS 记录配置建议
echo
echo "=================== DNS 配置指南 ==================="
echo "- 类型: A    主机名: @              内容: 您的服务器 IPv4 地址       TTL: 3600"
echo "- 类型: A    主机名: mail           内容: 您的服务器 IPv4 地址       TTL: 3600"
echo "- 类型: MX   主机名: @              内容: ${full_domain} (优先级10) TTL: 3600"
echo "- 类型: TXT  主机名: @              内容: \"v=spf1 mx ~all\"          TTL: 3600"
dkim_txt=$(sed -n 's/.*\"\(.*\)\".*/\1/p' /etc/opendkim/keys/${domain}/default.txt)
echo "- 类型: TXT  主机名: default._domainkey   内容: \"${dkim_txt}\"   TTL: 3600"
echo "- 类型: TXT  主机名: _dmarc         内容: \"v=DMARC1; p=none; rua=mailto:postmaster@${domain}\"   TTL: 3600"
echo
echo "注意：如果您使用 Cloudflare 等 DNS 服务，请将上述记录设置为“仅DNS”模式，以确保邮件收发正常。"
echo "===================================================="
echo

info "配置脚本执行完毕，请根据提示手动重启 Postfix、Dovecot 及 Apache 服务。"
