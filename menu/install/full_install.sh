#!/bin/bash 
clear

green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
cyan="\033[1;36m"
orange="\033[38;5;208m"
reset="\033[0m"

function info() {
  echo -e "${cyan}🔹 $1${reset}"
}

function success() {
  echo -e "${green}✅ $1${reset}"
}

function warning() {
  echo -e "${yellow}⚠️  $1${reset}"
}

function error_exit() {
  echo -e "${red}❌ $1${reset}"
  exit 1
}

# 计算标题居中
title="🛠️ 正在开始一键环境安装（含所有依赖）"
title_length=${#title}
total_width=83
padding=$(( (total_width - title_length) / 2 ))

echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
printf "%${padding}s" ""; echo -e "${orange}$title${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

info "📁 检查 /root/VPN 目录是否存在..."
if [ ! -d "/root/VPN" ]; then
  info "📁 正在创建 /root/VPN 目录..."
  mkdir -p /root/VPN || error_exit "❌ 创建 /root/VPN 目录失败"
  chmod 755 /root/VPN
  success "/root/VPN 创建完成"
else
  success "/root/VPN 已存在"
fi

cd /root/VPN || error_exit "无法进入 /root/VPN"

# 安装基础依赖前，检查是否已安装 dpkg
info "🔄 检查 dpkg 是否已安装..."
if ! command -v dpkg &> /dev/null; then
  info "dpkg 未安装，正在安装 dpkg..."
  apt update && apt install -y dpkg || error_exit "❌ dpkg 安装失败"
  success "dpkg 安装成功"
else
  success "dpkg 已安装"
fi

# 安装基础依赖（curl wget unzip socat tar sudo）
info "🔧 安装基础依赖（curl wget unzip socat tar sudo）..."
apt update && apt install -y curl wget unzip socat tar sudo && success "基础依赖安装完成" || error_exit "依赖安装失败"

info "🔓 启用 Universe 源..."
apt install -y software-properties-common && add-apt-repository universe -y && apt update && success "Universe 源启用成功" || warning "启用 Universe 源失败，可能已启用"

info "🧰 安装网络工具（mtr-tiny traceroute bmon）..."
apt install -y mtr-tiny traceroute bmon && success "网络工具安装完成" || warning "部分网络工具安装失败，请手动检查"

info "⬇️ 下载 Xray..."
wget -O Xray-linux-64.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && success "Xray 下载成功" || error_exit "Xray 下载失败"

info "📦 解压 Xray..."
unzip -o Xray-linux-64.zip -d xray && chmod +x xray/xray && success "Xray 解压并赋权完成" || error_exit "Xray 解压失败"

info "⬇️ 下载 Hysteria..."
# 检查是否已有文件，若有则提示用户是否删除
if [ -f "hysteria" ]; then
  warning "Hysteria 已存在，是否强行删除并继续安装？（y/n）"
  read -r choice
  if [[ "$choice" == [yY] ]]; then
    rm -f hysteria
    info "已删除旧版 Hysteria，开始重新下载..."
  else
    warning "跳过 Hysteria 下载，继续下一步安装"
    success "Hysteria 已跳过"
    exit 0
  fi
fi

wget -O hysteria https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64 && chmod +x hysteria && success "Hysteria 下载并赋权完成" || error_exit "Hysteria 下载失败"

info "⬇️ 下载 Cloudflared..."
wget -O cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && chmod +x cloudflared && success "Cloudflared 下载并赋权完成" || error_exit "Cloudflared 下载失败"

echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
info "🎉 所有组件和依赖已成功安装并保存在 /root/VPN"
echo -e "${yellow}📌 示例运行命令：${reset}"
echo -e "${yellow}▶ /root/VPN/xray/xray run -config /root/VPN/xray/config.json${reset}"
echo -e "${yellow}▶ /root/VPN/hysteria --config /root/VPN/hysteria.yaml${reset}"
echo -e "${yellow}▶ /root/VPN/cloudflared tunnel login${reset}"
echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

# 返回上级菜单
read -p "$(echo -e "${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/install_upgrade.sh
