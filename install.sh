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

# 输出美观的标题
echo -e "${blue}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "                           ${orange}🧰 超级工具箱 一键安装脚本${reset}"
echo -e "${blue}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e "      本脚本将执行以下操作："                                                      ${green}作者邮箱:${reset}${light_pink}MAIL@VSWSV.COM${reset}
echo -e "      ${green}1.${reset} 清理APT缓存并更新源"
echo -e "      ${green}2.${reset} 安装必要工具（GIT和CURL）"
echo -e "      ${green}3.${reset} 克隆或覆盖 GITHUB 仓库到 /root/VPN"
echo -e "      ${green}4.${reset} 设置 'vpn' 命令来快速启动菜单"
echo -e "${blue}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

read -p "$(echo -e ${yellow}是否继续安装？请输入 [Y/N]：${reset}) " answer

if [[ "$answer" != "Y" && "$answer" != "y" ]]; then
  echo -e "${red}❌ 用户取消安装，已退出。${reset}"
  exit 1
fi

# 清理APT缓存并更新源
echo -e "${green}🧹 正在清理APT缓存${reset}"
sudo apt-get clean

echo -e "${green}🌐 正在更新APT源${reset}"
sudo apt-get update --no-cache

# 安装必要工具
echo -e "${green}🔧 正在安装GIT和CURL${reset}"
sudo apt install -y git curl

# 检查 /root/VPN 目录是否存在
if [ -d "/root/VPN" ]; then
  echo -e "${yellow}⚠️ 发现已有 /root/VPN 目录存在正在覆盖${reset}"
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


# 设置快捷命令 vpn
if [ -f "/usr/local/bin/vpn" ]; then
  sudo rm -f /usr/local/bin/vpn
fi

sudo ln -s /root/VPN/menu.sh /usr/local/bin/vpn

# 成功提示
echo -e "${blue}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "              ${green}🎉 安装完成！现在你可以直接输入 ${yellow}vpn${green} 来启动菜单！${reset}"
echo -e "${blue}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
