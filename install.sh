#!/bin/bash

# 定义颜色
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
orange="\033[38;5;214m"
pink="\033[1;35m"
reset="\033[0m"
light_pink="\033[38;5;218m"

show_menu() {
echo -e "${blue}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "                           ${orange}🧰 超级工具箱 一键安装脚本${reset}"
echo -e "${blue}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e "      本脚本将执行以下操作：                            ${green}作者邮箱:${reset}${light_pink}MAIL@VSWSV.COM"
echo -e "      ${green}1.${reset} 清理APT缓存并更新源"
echo -e "      ${green}2.${reset} 安装必要工具 GIT和CUR"
echo -e "      ${green}3.${reset} 克隆或覆盖 GITHUB 仓库到 /ROOT/VPN"
echo -e "      ${green}4.${reset} 设置 'vpn' 命令来快速启动菜单"
echo -e "${blue}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

read -p "$(echo -e ${yellow}是否继续安装？请输入 [Y/N]：${reset}) " answer

if [[ "$answer" != "Y" && "$answer" != "y" ]]; then
  echo -e "${red}❌ 用户取消安装，已退出。${reset}"
  exit 1
fi

# 清理APT缓存并更新源
echo -e "${green}🧹 正在清理APT缓存${reset}"
sudo apt-get clean && echo -e "${green}✅ 清理完成${reset}"

echo -e "${green}🌐 正在更新APT源${reset}"
if sudo apt-get update; then
  echo -e "${green}✅ APT 源更新成功${reset}"
else
  echo -e "${red}❌ APT 源更新失败，请检查网络${reset}"
  exit 1
fi
# 安装必要工具
echo -e "${green}🔧 正在安装 GIT和CURL${reset}"
if sudo apt install -y git curl; then
  echo -e "${green}✅ GIT和CURL 安装完成${reset}"
else
  echo -e "${red}❌ 安装失败，请检查网络或软件源配置${reset}"
  exit 1
fi
# 检查 /root/VPN 目录是否存在
if [ -d "/root/VPN" ]; then
  echo -e "${yellow}⚠️ 发现已有 /ROOT/VPN 目录存在正在覆盖${reset}"
  sudo rm -rf /root/VPN
fi

# 克隆仓库
echo -e "${green}📥 正在克隆 GITHUB 仓库...${reset}"
if git clone https://github.com/VSWSV/VPN.git /root/VPN; then
  echo -e "${green}✅ 克隆成功！${reset}"
else
  echo -e "${red}❌ 克隆失败，请检查网络连接或仓库地址。${reset}"
  exit 1
fi

# 设置权限
chmod -R +x /root/VPN


# 输入自定义命令并检测冲突/是否覆盖
while true; do
  read -p "$(echo -e ${yellow}请输入你要设置启动命令：${reset}) " custom_command
  if [[ -z "$custom_command" ]]; then
    echo -e "${red}❌ 命令不能为空，请重新输入${reset}"
    continue
  fi

  if command -v $custom_command &> /dev/null; then
    echo -e "${yellow}⚠️ 命令 '${custom_command}' 已存在,是否覆盖？ [Y/N] ${reset}"
    read -p "" overwrite
    if [[ "$overwrite" == "Y" || "$overwrite" == "y" ]]; then
      sudo rm -f /usr/local/bin/$custom_command
      sudo ln -s /root/VPN/menu.sh /usr/local/bin/$custom_command
      echo -e "${green}✅ 命令 '${custom_command}' 已成功覆盖并设置！${reset}"
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

# 安装完成提示
echo -e "${blue}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "              ${green}🎉 安装完成！现在你可以直接输入 ${reset}${custom_command}${green} 来启动菜单！${reset}"
echo -e "${blue}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
