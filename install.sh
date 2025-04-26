#!/bin/bash

clear

green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
orange="\033[38;5;214m"
pink="\033[1;35m"
reset="\033[0m"
light_pink="\033[38;5;218m"

echo -e "${blue}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "                           ${orange}🧰 超级工具箱 一键安装脚本${reset}"
echo -e "${blue}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e "      本脚本将执行以下操作：                            ${green}作者邮箱:${reset}${light_pink}MAIL@VSWSV.COM"
echo -e "      ${green}1.${reset} 清理APT缓存并更新源"
echo -e "      ${green}2.${reset} 禁用APT后台自动升级（防止APT锁卡死）"
echo -e "      ${green}3.${reset} 安装必要工具 GIT和CURL"
echo -e "      ${green}4.${reset} 克隆或覆盖 GITHUB 仓库到 /ROOT/VPN"
echo -e "      ${green}5.${reset} 设置 '自定义' 命令来快速启动菜单"
echo -e "      ${green}6.${reset} 修改密码-美化显示-开启IPV6-SSH 保活"
echo -e "${blue}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

read -p "$(echo -e ${yellow}是否继续安装？请输入 [Y/N]：${reset}) " answer

if [[ "$answer" != "Y" && "$answer" != "y" ]]; then
  echo -e "${red}❌ 用户取消安装，已退出。${reset}"
  exit 1
fi

# 1. 清理APT缓存
echo -e "${green}🧹 正在清理APT缓存${reset}"
sudo apt-get clean && echo -e "${green}✅ 清理完成${reset}"

# 2. 更新APT源
echo -e "${green}🌐 正在更新APT源${reset}"
if sudo apt-get update; then
  echo -e "${green}✅ APT源更新成功${reset}"
else
  echo -e "${red}❌ APT源更新失败，请检查网络${reset}"
  exit 1
fi

# 3. 禁用APT后台自动升级
echo -e "${green}🚫 正在禁用APT后台自动升级服务...${reset}"
systemctl stop apt-daily.service apt-daily-upgrade.service
systemctl disable apt-daily.service apt-daily-upgrade.service
systemctl mask apt-daily.service apt-daily-upgrade.service
echo -e "${green}✅ APT后台自动升级已禁用${reset}"
sleep 1

# 4. 安装GIT和CURL
echo -e "${green}🔧 正在安装GIT和CURL${reset}"
if sudo apt install -y git curl; then
  echo -e "${green}✅ GIT和CURL安装完成${reset}"
else
  echo -e "${red}❌ 安装失败，请检查网络或源配置${reset}"
  exit 1
fi

# 5. 克隆GitHub仓库
if [ -d "/root/VPN" ]; then
  echo -e "${yellow}⚠️ 发现已有 /root/VPN，正在覆盖${reset}"
  sudo rm -rf /root/VPN
fi

echo -e "${green}📥 正在克隆GitHub仓库...${reset}"
if git clone https://github.com/VSWSV/VPN.git /root/VPN; then
  echo -e "${green}✅ 克隆成功${reset}"
else
  echo -e "${red}❌ 克隆失败，请检查网络或仓库地址${reset}"
  exit 1
fi

chmod -R +x /root/VPN

# 6. 设置自定义启动命令
while true; do
  read -p "$(echo -e ${yellow}请输入你要设置启动命令：${reset}) " custom_command
  if [[ -z "$custom_command" ]]; then
    echo -e "${red}❌ 命令不能为空，请重新输入${reset}"
    continue
  fi

  if command -v $custom_command &> /dev/null; then
    echo -e "${yellow}⚠️ 命令 '${custom_command}' 已存在，是否覆盖？ [Y/N] ${reset}"
    read -p "" overwrite
    if [[ "$overwrite" == "Y" || "$overwrite" == "y" ]]; then
      sudo rm -f /usr/local/bin/$custom_command
      sudo ln -s /root/VPN/menu.sh /usr/local/bin/$custom_command
      echo -e "${green}✅ 命令 '${custom_command}' 已成功覆盖并设置${reset}"
      break
    else
      echo -e "${red}❌ 未覆盖，重新输入命令名...${reset}"
      continue
    fi
  else
    sudo ln -s /root/VPN/menu.sh /usr/local/bin/$custom_command
    echo -e "${green}✅ 已成功设置命令 '${custom_command}' 来启动主菜单！${reset}"
    break
  fi
done

# 7. 系统安全优化
echo -e "${green}🔐 正在进行系统安全与终端美化优化...${reset}"

# 修改密码
echo -e "${yellow}➤ 修改当前用户密码...${reset}"
if passwd; then
  echo -e "${green}✅ 密码修改成功${reset}"
else
  echo -e "${red}❌ 密码修改失败，请手动检查${reset}"
fi

# 禁用 MOTD
echo -e "${yellow}➤ 禁用 MOTD 动态欢迎信息...${reset}"
if chmod -x /etc/update-motd.d/*; then
  echo -e "${green}✅ MOTD已禁用${reset}"
else
  echo -e "${red}❌ 禁用失败，可能文件不存在${reset}"
fi

# 美化登录信息
echo -e "${yellow}➤ 创建美化终端信息脚本...${reset}"
cat << 'EOF' > /etc/profile.d/motd.sh
#!/bin/bash
function bar() {
  local percent=$1
  local blocks=$((percent * 50 / 100))
  local empty=$((50 - blocks))
  local bar=""
  local color="\033[0;32m"
  if (( percent >= 80 )); then color="\033[0;31m"
  elif (( percent >= 60 )); then color="\033[0;33m"; fi
  for ((i = 0; i < blocks; i++)); do bar+="▓"; done
  for ((i = 0; i < empty; i++)); do bar+="░"; done
  echo -e "$color$bar\033[0m"
}
load=$(uptime | awk -F'load average: ' '{print $2}' | cut -d, -f1)
cpu_perc=$(awk -v l="$load" 'BEGIN { printf("%.0f", l*10) }')
cpu_bar=$(bar $cpu_perc)
mem_used=$(free | awk '/Mem:/ {printf("%.0f", $3/$2*100)}')
mem_bar=$(bar $mem_used)
disk_used=$(df / | awk 'END {print $5}' | tr -d '%')
disk_bar=$(bar $disk_used)
swap_used=$(free | awk '/Swap:/ { if ($2==0) print 0; else printf("%.0f", $3/$2*100) }')
swap_bar=$(bar $swap_used)
ipv4=$(hostname -I | awk '{print $1}')
ipv6=$(ip -6 addr show scope global | awk '/inet6/ {print $2}' | cut -d/ -f1 | head -n 1)
current_time=$(date +"%Y-%m-%d %H:%M:%S")
echo 
echo -e "CPU 使用率:        $cpu_bar  $cpu_perc%"
echo
echo -e "内存使用率:        $mem_bar  ${mem_used}%"
echo
echo -e "磁盘占用率:        $disk_bar  ${disk_used}%"
echo
echo -e "空间使用率:        $swap_bar  ${swap_used}%"
echo
echo -e "公网 IPv4 地址:    \033[1;33m$ipv4\033[0m"
echo
echo -e "公网 IPv6 地址:    \033[1;36m$ipv6\033[0m"
echo
echo -e "当前时间:          \033[1;34m$current_time\033[0m"
echo
EOF

chmod +x /etc/profile.d/motd.sh && source /etc/profile.d/motd.sh
touch ~/.hushlogin && echo -e "${green}✅ MOTD脚本启用成功${reset}"

# SSH 保活
echo -e "${yellow}➤ 配置SSH保活...${reset}"
sed -i 's/#ClientAliveInterval.*/ClientAliveInterval 60/' /etc/ssh/sshd_config
sed -i 's/#ClientAliveCountMax.*/ClientAliveCountMax 3/' /etc/ssh/sshd_config
systemctl restart sshd && echo -e "${green}✅ SSH配置修改成功${reset}"

# 开启IPv6
echo -e "${yellow}➤ 启用IPv6支持...${reset}"
sed -i 's/^net\\.ipv6\\.conf\\.all\\.disable_ipv6 = 1/#&/' /etc/sysctl.conf
sed -i 's/^net\\.ipv6\\.conf\\.default\\.disable_ipv6 = 1/#&/' /etc/sysctl.conf
sed -i 's/^net\\.ipv6\\.conf\\.lo\\.disable_ipv6 = 1/#&/' /etc/sysctl.conf
sysctl -p && echo -e "${green}✅ IPv6设置已应用${reset}"

# 完成提示
echo -e "${blue}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "              ${green}🎉 安装完成！现在你可以输入 ${yellow}${custom_command}${green} 来启动菜单！${reset}"
echo -e "${blue}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
