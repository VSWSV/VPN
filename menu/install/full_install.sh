#!/bin/bash

set -e

# 颜色定义
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
bold="\033[1m"
reset="\033[0m"

function info() {
  echo -e "${blue}🔹 $1${reset}"
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

info "📁 检查 /root/VPN 目录是否存在..."
if [ -d "/root/VPN" ]; then
  success "/root/VPN 已存在，继续使用该目录"
else
  info "📁 创建 /root/VPN 目录..."
  mkdir -p /root/VPN || error_exit "无法创建目录 /root/VPN"
  chmod 755 /root/VPN
  success "/root/VPN 创建成功"
fi

cd /root/VPN || error_exit "无法进入目录 /root/VPN"

info "🔍 安装依赖项（curl unzip tar sudo wget socat）..."
apt update && apt install -y curl unzip tar sudo wget socat && success "依赖项安装成功" || error_exit "依赖项安装失败"

# 下载 Xray 压缩包并解压
info "⬇️ 下载 Xray 压缩包..."
wget -O Xray-linux-64.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip && success "Xray 下载成功" || error_exit "Xray 下载失败"

info "📦 解压 Xray..."
unzip -o Xray-linux-64.zip -d xray && chmod +x xray/xray && success "Xray 解压并赋权成功" || error_exit "Xray 解压失败"

# 下载 Hysteria 裸文件
info "⬇️ 下载 Hysteria 可执行文件..."
wget -O hysteria https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64 && chmod +x hysteria && success "Hysteria 下载并赋权成功" || error_exit "Hysteria 下载失败"

# 下载 cloudflared 裸文件
info "⬇️ 下载 Cloudflared 可执行文件..."
wget -O cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 && chmod +x cloudflared && success "Cloudflared 下载并赋权成功" || error_exit "Cloudflared 下载失败"

# 移动到系统路径
info "🚚 安装 Xray 到系统路径..."
sudo mv xray/xray /usr/local/bin/xray && success "Xray 安装到 /usr/local/bin"

info "🚚 安装 Hysteria 到系统路径..."
sudo mv hysteria /usr/local/bin/hysteria && success "Hysteria 安装到 /usr/local/bin"

info "🚚 安装 Cloudflared 到系统路径..."
sudo mv cloudflared /usr/local/bin/cloudflared && success "Cloudflared 安装到 /usr/local/bin"

# 最终反馈
echo -e "${green}🎉 所有组件已成功安装并可全局使用！${reset}"
echo -e "${blue}📌 请执行以下命令进行 Cloudflare 隧道授权：${reset}"
echo -e "${yellow}   cloudflared tunnel login${reset}"
