#!/bin/bash 

clear

# 颜色定义
cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
orange="\033[38;5;214m"
reset="\033[0m"

# 成功失败统计
success_all=0
fail_all=0

echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "                               ${orange}📬 Roundcube配置器${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

# 检查并创建 Roundcube 目录
if [ ! -d "/var/www/html/roundcube" ]; then
  echo -e "${yellow}⚡ 检测到 /var/www/html/roundcube 目录不存在，正在创建...${reset}"
  mkdir -p /var/www/html/roundcube
  chown -R www-data:www-data /var/www/html/roundcube
  chmod -R 755 /var/www/html/roundcube
  echo -e "${green}✅ 创建并配置 /var/www/html/roundcube 目录成功${reset}"
fi

# 输入Roundcube Web访问端口
read -p "$(echo -e ${yellow}▶ 请输入Roundcube Web访问端口（默认35500）：${reset}) " web_port
web_port=${web_port:-35500}
echo -e "${green}📝 输入的Web访问端口为：$web_port${reset}"

# 配置 Roundcube 数据库连接
echo -e "⚙️ 配置 Roundcube 数据库连接..."
config_file="/var/www/html/roundcube/config/config.inc.php"
if [ ! -f "$config_file" ]; then
  echo -e "${red}❌ 找不到配置文件 $config_file，请确保Roundcube已经正确下载和解压。${reset}"
  exit 1
else
  echo -e "${green}📝 数据库连接已配置至：$config_file${reset}"
fi

# 配置 Web 服务器（Apache / Nginx）
echo -e "⚙️ 配置 Web 服务器（Apache / Nginx）..."
apache_config="/etc/apache2/sites-available/roundcube.conf"
if [ -f "$apache_config" ]; then
  echo -e "${green}📝 Apache 配置已更新：$apache_config${reset}"
else
  echo -e "${red}❌ Apache 配置文件未找到，请检查安装步骤。${reset}"
  exit 1
fi

# 检查 Roundcube 文件权限
echo -e "⚙️ 检查 Roundcube 文件权限..."
if [ -d "/var/www/html/roundcube" ]; then
  chown -R www-data:www-data /var/www/html/roundcube
  chmod -R 755 /var/www/html/roundcube
  echo -e "${green}✔️ 文件权限配置成功！${reset}"
else
  echo -e "${red}❌ 找不到 /var/www/html/roundcube 目录，请检查目录是否存在！${reset}"
  exit 1
fi

# 测试 Roundcube 访问
echo -e "🔧 测试 Roundcube 访问..."
echo -e "${green}🌍 访问链接：https://mail.vswsv.com:$web_port/roundcube${reset}"

echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

# 配置完成总结
echo -e "${green}✔️ Roundcube配置完成！${reset}"

# 返回数据库管理菜单
read -p "$(echo -e "💬 按回车键返回数据库管理菜单...${reset}")" dummy
bash /root/VPN/menu/mail.sh
