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
draw_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                               ${orange}📬 Roundcube配置器${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

draw_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 返回上级菜单
return_menu() {
  read -p "$(echo -e "💬 ${cyan}按回车键返回数据库管理菜单...${reset}")" dummy
  bash /root/VPN/menu/mail.sh
}

# 获取 Roundcube 目录
get_roundcube_dir() {
  # 默认 Roundcube 目录路径
  rc_dir="/var/www/html/roundcube"
  echo "$rc_dir"
}

# 获取 Roundcube 配置文件路径
get_roundcube_config() {
  # 默认配置文件路径
  rc_config_file="/var/www/html/roundcube/config/config.inc.php"
  echo "$rc_config_file"
}

# 配置 Roundcube
clear
draw_header

# 输入Web访问端口
read -p "$(echo -e "${yellow}▶ 请输入Roundcube Web访问端口（默认35500）：${reset}")" port
port=${port:-35500}

# 显示端口确认
echo -e "${blue}📝 输入的Web访问端口为：${green}$port${reset}"

# 获取 Roundcube 配置文件
rc_config_file=$(get_roundcube_config)

# 配置 Roundcube 数据库连接
echo -e "${yellow}⚙️ 配置 Roundcube 数据库连接...${reset}"
echo -e "\$config['db_dsnw'] = 'mysql://mail_admin:password@localhost/maildb';" >> "$rc_config_file"
echo -e "${blue}📝 数据库连接已配置至：${green}$rc_config_file${reset}"

# 配置 Apache / Nginx
echo -e "${yellow}⚙️ 配置 Web 服务器（Apache / Nginx）...${reset}"

# 配置 Apache (如果需要，可以添加 Nginx 配置)
apache_config="/etc/apache2/sites-available/roundcube.conf"
echo "<VirtualHost *:$port>" > "$apache_config"
echo "  ServerName mail.vswsv.com" >> "$apache_config"
echo "  DocumentRoot /var/www/html/roundcube" >> "$apache_config"
echo "  SSLEngine on" >> "$apache_config"
echo "  SSLCertificateFile /etc/letsencrypt/live/mail.vswsv.com/fullchain.pem" >> "$apache_config"
echo "  SSLCertificateKeyFile /etc/letsencrypt/live/mail.vswsv.com/privkey.pem" >> "$apache_config"
echo "</VirtualHost>" >> "$apache_config"
echo -e "${blue}📝 Apache 配置已更新：${green}$apache_config${reset}"

# 检查权限
echo -e "${yellow}⚙️ 检查 Roundcube 文件权限...${reset}"
chown -R www-data:www-data /var/www/html/roundcube
chmod -R 755 /var/www/html/roundcube
echo -e "${green}✔️ 文件权限配置成功！${reset}"

# 测试 Roundcube 访问
echo -e "${yellow}🔧 测试 Roundcube 访问...${reset}"
echo -e "${blue}🌍 访问链接：https://mail.vswsv.com:$port/roundcube${reset}"

# 完成
draw_footer
echo -e "${green}✔️ Roundcube配置完成！${reset}"
return_menu
