#!/bin/bash

# 颜色定义
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
cyan="\033[1;36m"
orange="\033[38;5;214m"
reset="\033[0m"

# 边框函数
function draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                               ${orange}📬 邮局系统配置向导${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

function return_menu() {
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  bash /root/VPN/menu/mail.sh
}

# 自动检测IP
ipv4=$(curl -s4 ip.sb)
ipv6=$(curl -s6 ip.sb)

while true; do
  clear
  draw_header

  echo -e "  ${yellow}①${reset} ${green}建数据库${reset}        ${yellow}②${reset} ${green}设主机名域名${reset}     ${yellow}③${reset} ${green}DNS引导${reset}"
  echo -e "  ${yellow}④${reset} ${green}SSL证书${reset}          ${yellow}⑤${reset} ${green}设Postfix${reset}        ${yellow}⑥${reset} ${green}设Dovecot${reset}"
  echo -e "   ${yellow}⓪${reset} ${red}返回主菜单${reset}"

  draw_footer

  read -p "请输入选项编号：" opt
  case $opt in
    1)
      clear
      draw_header
      echo -e "${cyan}▶ 请输入数据库名称：${reset}"
      read dbname
      echo -e "${cyan}▶ 请输入数据库用户名：${reset}"
      read dbuser
      echo -e "${cyan}▶ 请输入数据库用户密码：${reset}"
      read dbpass
      echo -e "${cyan}▶ 请再次确认数据库用户密码：${reset}"
      read dbpass_confirm

      if [ "$dbpass" != "$dbpass_confirm" ]; then
        echo -e "${red}❌ 两次输入的密码不一致！${reset}"
        return_menu
      fi

      mysql -u root -p <<EOF
CREATE DATABASE IF NOT EXISTS ${dbname} DEFAULT CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS '${dbuser}'@'localhost' IDENTIFIED BY '${dbpass}';
GRANT ALL PRIVILEGES ON ${dbname}.* TO '${dbuser}'@'localhost';
FLUSH PRIVILEGES;
EOF

      cd /root/VPN/MAIL/roundcube
      mysql -u ${dbuser} -p${dbpass} ${dbname} < SQL/mysql.initial.sql

      echo -e "${green}✅ 数据库配置完成！${reset}"
      return_menu
      ;;
    2)
      clear
      draw_header
      echo -e "${cyan}▶ 请输入您的邮件域名 (如 example.com)：${reset}"
      read domain
      echo -e "${cyan}▶ 请输入服务器主机名 (如 mail.example.com)：${reset}"
      read hostname

      postconf -e "myhostname = $hostname"
      postconf -e "mydomain = $domain"
      postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"

      DOVECOT_CONF="/etc/dovecot/conf.d/10-ssl.conf"
      sed -i "/ssl_cert/s|.*|ssl_cert = </etc/letsencrypt/live/${hostname}/fullchain.pem|" $DOVECOT_CONF
      sed -i "/ssl_key/s|.*|ssl_key = </etc/letsencrypt/live/${hostname}/privkey.pem|" $DOVECOT_CONF

      echo -e "${green}✅ 域名配置完成！${reset}"
      echo -e "${blue}🌍 Roundcube访问地址: https://${hostname}/roundcube${reset}"
      return_menu
      ;;
    3)
      clear
      draw_header
      echo -e "${cyan}▶ 请输入管理员接收邮箱（用于DMARC反馈）：${reset}"
      read admin_mail
      echo -e "${green}▶ 请在你的域名后台添加以下DNS记录（TTL建议300秒）：${reset}"
      echo -e "${yellow}A记录： mail -> ${ipv4}${reset}"
      if [ -n "$ipv6" ]; then
        echo -e "${yellow}AAAA记录： mail -> ${ipv6}${reset}"
      fi
      echo -e "${yellow}MX记录： @ -> mail.${hostname} 优先级10${reset}"
      echo -e "${yellow}TXT记录（SPF）：@ -> v=spf1 mx ~all${reset}"
      echo -e "${yellow}TXT记录（DMARC）：_dmarc -> v=DMARC1; p=none; rua=mailto:${admin_mail}${reset}"
      echo -e "${yellow}TXT记录（DKIM）：待OpenDKIM配置后添加${reset}"
      return_menu
      ;;
    4)
      clear
      draw_header
      echo -e "${cyan}▶ 请输入申请SSL证书的域名（如 mail.example.com）：${reset}"
      read certdomain
      systemctl stop apache2
      certbot certonly --standalone -d "$certdomain"
      systemctl start apache2
      if [ -f "/etc/letsencrypt/live/${certdomain}/fullchain.pem" ]; then
        echo -e "${green}✅ SSL证书申请成功，证书路径已生成！${reset}"
      else
        echo -e "${red}❌ SSL证书申请失败，请检查域名解析或防火墙！${reset}"
      fi
      return_menu
      ;;
    5)
      clear
      draw_header
      echo -e "${cyan}▶ 正在配置Postfix参数...${reset}"
      postconf -e "myhostname = $hostname"
      postconf -e "mydestination = localhost"
      postconf -e "inet_interfaces = all"
      postconf -e "inet_protocols = all"
      postconf -e "smtpd_tls_cert_file = /etc/letsencrypt/live/${hostname}/fullchain.pem"
      postconf -e "smtpd_tls_key_file = /etc/letsencrypt/live/${hostname}/privkey.pem"
      postconf -e "smtpd_use_tls = yes"
      postconf -e "smtpd_tls_auth_only = yes"
      postconf -e "smtpd_sasl_auth_enable = yes"
      systemctl restart postfix
      echo -e "${green}✅ Postfix配置完成！${reset}"
      return_menu
      ;;
    6)
      clear
      draw_header
      echo -e "${cyan}▶ 正在配置Dovecot参数...${reset}"
      sed -i 's/#disable_plaintext_auth = yes/disable_plaintext_auth = yes/' /etc/dovecot/conf.d/10-auth.conf
      sed -i 's/#ssl = yes/ssl = yes/' /etc/dovecot/conf.d/10-ssl.conf
      sed -i "s|#ssl_cert = <.*|ssl_cert = </etc/letsencrypt/live/${hostname}/fullchain.pem|" /etc/dovecot/conf.d/10-ssl.conf
      sed -i "s|#ssl_key = <.*|ssl_key = </etc/letsencrypt/live/${hostname}/privkey.pem|" /etc/dovecot/conf.d/10-ssl.conf
      systemctl restart dovecot
      echo -e "${green}✅ Dovecot配置完成！${reset}"
      return_menu
      ;;
    0)
      bash /root/VPN/menu/mail.sh
      ;;
    *)
      echo -e "${red}❌ 无效输入，请重新选择！${reset}"
      sleep 1
      ;;
  esac
done
