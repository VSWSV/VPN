#!/bin/bash

# Colors
blue="\033[1;34m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
cyan="\033[1;36m"
reset="\033[0m"

# Border functions (80 ═)
draw_top() {
  echo -e "${cyan}╔$(printf '═%.0s' {1..80})╗${reset}"
}
draw_mid() {
  echo -e "${cyan}╠$(printf '═%.0s' {1..80})╣${reset}"
}
draw_bottom() {
  echo -e "${cyan}╚$(printf '═%.0s' {1..80})╝${reset}"
}

draw_top
echo -e "${orange}                  📮 邮局系统一键部署                ${reset}"
draw_mid

# 清理APT锁和修复dpkg
echo -e "${orange}⚙️ 清理APT锁和修复dpkg${reset}"
if pgrep -x "apt" >/dev/null; then
    echo -e "${yellow}⚠ 检测到APT进程，正在终止...${reset}"
    killall -9 apt apt-get dpkg 2>/dev/null
fi
rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock*
dpkg --configure -a
apt-get update -y
apt-get --fix-broken install -y
if [ $? -ne 0 ]; then
    echo -e "${red}✗ APT修复失败，请检查网络和APT状态${reset}"
    exit 1
fi

# ① 更新软件包列表
echo -e "${orange}① 更新软件包列表...${reset}"
apt-get update >> /dev/null 2>&1
if [ $? -eq 0 ]; then
  echo -e "${green}✓ 更新完成${reset}"
else
  echo -e "${red}✗ 更新失败${reset}"
  exit 1
fi

# ② 安装系统工具
echo -e "${orange}② 安装系统工具...${reset}"
for pkg in tree curl wget openssl net-tools; do
    if dpkg -l | grep -qw "$pkg"; then
        echo -e "${yellow}⚠ 已安装: ${green}$pkg${reset}"
    else
        apt-get install -y $pkg >> /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${green}✓ 安装成功: ${reset}$pkg"
        else
            echo -e "${red}✗ 安装失败: ${reset}$pkg"
            exit 1
        fi
    fi
done

# 读取域名和管理员信息
echo -e ""
read -p "$(echo -e "${yellow}✨ 请输入邮件域名 (例如: example.com): ${reset}")" DOMAIN
if [ -z "$DOMAIN" ]; then
    echo -e "${red}✗ 域名不能为空${reset}"
    exit 1
fi
read -p "$(echo -e "${yellow}✨ 请输入服务器主机名 (例如: mail.${DOMAIN}): ${reset}")" HOSTNAME
if [ -z "$HOSTNAME" ]; then
    HOSTNAME="mail.${DOMAIN}"
    echo -e "${blue}📝 服务器主机名设置为: ${green}$HOSTNAME${reset}"
fi
ADMIN_USER="postmaster"
read -p "$(echo -e "${yellow}✨ 请输入管理员用户名 (默认: postmaster): ${reset}")" input_user
if [ -n "$input_user" ]; then
    ADMIN_USER="$input_user"
fi
read -p "$(echo -e "${yellow}✨ 请输入管理员密码: ${reset}")" -s ADMIN_PASS
echo -e ""
if [ -z "$ADMIN_PASS" ]; then
    echo -e "${red}✗ 密码不能为空${reset}"
    exit 1
fi

# ③ 安装MySQL数据库
echo -e "${orange}③ 安装MySQL数据库...${reset}"
if ! dpkg -l | grep -q mysql-server; then
  debconf-set-selections <<< "mysql-server mysql-server/root_password password "
  debconf-set-selections <<< "mysql-server mysql-server/root_password_again password "
  apt-get install -y mysql-server >> /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${green}✓ MySQL安装成功${reset}"
  else
    echo -e "${red}✗ MySQL安装失败${reset}"
    exit 1
  fi
else
  echo -e "${yellow}⚠ MySQL已安装，跳过${reset}"
fi

# ④ 安装邮件服务 (Postfix, Dovecot)
echo -e "${orange}④ 安装邮件服务(Postfix, Dovecot)...${reset}"
for pkg in postfix postfix-mysql dovecot-core dovecot-imapd dovecot-pop3d dovecot-mysql; do
    if dpkg -l | grep -qw "$pkg"; then
        echo -e "${yellow}⚠ 已安装: ${green}$pkg${reset}"
    else
        DEBIAN_FRONTEND=noninteractive apt-get install -y $pkg >> /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${green}✓ 安装成功: ${reset}$pkg"
        else
            echo -e "${red}✗ 安装失败: ${reset}$pkg"
            exit 1
        fi
    fi
done

# ⑤ 安装Web服务 (Apache, PHP)
echo -e "${orange}⑤ 安装Web服务(Apache, PHP)...${reset}"
for pkg in apache2 libapache2-mod-php php php-mysql php-intl php-curl php-gd php-mbstring php-xml php-zip; do
    if dpkg -l | grep -qw "$pkg"; then
        echo -e "${yellow}⚠ 已安装: ${green}$pkg${reset}"
    else
        apt-get install -y $pkg >> /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${green}✓ 安装成功: ${reset}$pkg"
        else
            echo -e "${red}✗ 安装失败: ${reset}$pkg"
            exit 1
        fi
    fi
done

# ⑥ 部署Roundcube Webmail
echo -e "${orange}⑥ 部署Roundcube Webmail...${reset}"
if [ -d "/var/www/roundcube" ]; then rm -rf /var/www/roundcube; fi
RC_VERSION="1.6.3"
if wget -q https://github.com/roundcube/roundcubemail/releases/download/${RC_VERSION}/roundcubemail-${RC_VERSION}-complete.tar.gz -O /tmp/roundcube.tar.gz && tar -xzf /tmp/roundcube.tar.gz -C /var/www && mv /var/www/roundcubemail-${RC_VERSION} /var/www/roundcube && chown -R www-data:www-data /var/www/roundcube; then
    rm -f /tmp/roundcube.tar.gz
    echo -e "${green}✓ Roundcube部署成功${reset}"
else
    echo -e "${red}✗ Roundcube部署失败${reset}"
    exit 1
fi

# ⑦ 初始化Roundcube数据库
echo -e "${orange}⑦ 初始化Roundcube数据库...${reset}"
DB_NAME="roundcubedb"
DB_USER="roundcube"
DB_PASS="roundcube_password"
mysql -uroot <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT
mysql -uroot $DB_NAME < /var/www/roundcube/SQL/mysql.initial.sql 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${green}✓ 数据库初始化完成${reset}"
else
    echo -e "${red}✗ 数据库初始化失败${reset}"
    exit 1
fi

# 配置Roundcube
RC_CONFIG="/var/www/roundcube/config/config.inc.php"
cp /var/www/roundcube/config/config.inc.php.sample $RC_CONFIG
sed -i "s/\\['db_dsnw'\\] = ''/\\['db_dsnw'\\] = 'mysql:\\/\\/$DB_USER:$DB_PASS@localhost\\/$DB_NAME'/g" $RC_CONFIG
echo "\$config['default_host'] = 'localhost';" >> $RC_CONFIG
echo "\$config['smtp_server'] = 'localhost';" >> $RC_CONFIG
echo "\$config['smtp_port'] = 25;" >> $RC_CONFIG
echo "\$config['smtp_user'] = '%u';" >> $RC_CONFIG
echo "\$config['smtp_pass'] = '%p';" >> $RC_CONFIG
echo "\$config['username_domain'] = '$DOMAIN';" >> $RC_CONFIG
echo "\$config['des_key'] = '$(openssl rand -hex 32)';" >> $RC_CONFIG
echo "\$config['language'] = 'zh_CN';" >> $RC_CONFIG
chown www-data:www-data $RC_CONFIG

# ⑧ 配置Postfix和Dovecot (域名, SMTP认证)
echo -e "${orange}⑧ 配置邮件域名和认证...${reset}"
postconf -e "myhostname = $HOSTNAME"
postconf -e "mydomain = $DOMAIN"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_use_tls = no"
sed -i "s/#disable_plaintext_auth = yes/disable_plaintext_auth = no/" /etc/dovecot/conf.d/10-auth.conf
sed -i "s/#auth_mechanisms = plain/auth_mechanisms = plain login/" /etc/dovecot/conf.d/10-auth.conf
cat << 'EOF' >> /etc/dovecot/conf.d/10-master.conf

service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0666
    user = postfix
    group = postfix
  }
}
EOF
systemctl restart postfix dovecot apache2

# ⑨ 创建管理员邮箱账户
echo -e "${orange}⑨ 创建管理员邮箱账户...${reset}"
if id -u "$ADMIN_USER" >/dev/null 2>&1; then
    echo -e "${yellow}⚠ 系统用户已存在: ${green}$ADMIN_USER${reset}"
else
    adduser --disabled-password --gecos "" $ADMIN_USER >> /dev/null 2>&1
    echo "$ADMIN_USER:$ADMIN_PASS" | chpasswd
    echo -e "${green}✓ 已创建系统用户: ${reset}$ADMIN_USER"
fi

echo -e "${green}✅ 安装部署完成！${reset}"
echo -e "${blue}🌐 Roundcube访问: ${green}http://$HOSTNAME/roundcube${reset}"
echo -e "${blue}✉️ 管理邮箱: ${green}$ADMIN_USER@$DOMAIN${reset}"
draw_bottom
