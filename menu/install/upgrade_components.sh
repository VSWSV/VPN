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
title="🔄 功能升级更新"
title_length=${#title}
total_width=83
padding=$(( (total_width - title_length) / 2 ))

echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
printf "%${padding}s" ""; echo -e "${orange}$title${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

# 检查VPN目录是否存在
info "检查 /root/VPN 目录..."
if [ ! -d "/root/VPN" ]; then
  error_exit "/root/VPN 目录不存在，请先运行安装脚本"
else
  success "/root/VPN 目录存在"
fi

cd /root/VPN || error_exit "无法进入 /root/VPN"

# 版本规范化函数
function normalize_version() {
  echo "$1" | sed 's/^v//;s/[^0-9.]//g'
}

# 检查组件更新
info "检查组件更新..."

# Xray 检查
if [ -f "/root/VPN/xray/xray" ]; then
  current_xray=$("/root/VPN/xray/xray" version | head -n 1 | awk '{print $2}')
  latest_xray=$(curl -sL "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep '"tag_name":' | cut -d'"' -f4)
  
  if [ "$(normalize_version "$current_xray")" != "$(normalize_version "$latest_xray")" ]; then
    warning "Xray 有新版本可用: $latest_xray (当前: $current_xray)"
  else
    success "Xray 已是最新版本: $current_xray"
  fi
else
  warning "Xray 未安装"
fi

# Hysteria 检查
if [ -f "/root/VPN/hysteria" ]; then
  current_hysteria=$("/root/VPN/hysteria" version | awk 'NR==1{print $3}' | tr -d '\n')
  latest_hysteria=$(curl -sL "https://api.github.com/repos/apernet/hysteria/releases/latest" | grep '"tag_name":' | cut -d'"' -f4)
  
  if [ "$(normalize_version "$current_hysteria")" != "$(normalize_version "$latest_hysteria")" ]; then
    warning "Hysteria 有新版本可用: $latest_hysteria"
    info "当前版本: $current_hysteria"
  else
    success "Hysteria 已是最新版本: $current_hysteria"
  fi
else
  warning "Hysteria 未安装"
fi

# Cloudflared 检查
if [ -f "/root/VPN/cloudflared" ]; then
  current_cloudflared=$("/root/VPN/cloudflared" version | grep -oP 'cloudflared version \K[\d.]+')
  latest_cloudflared=$(curl -sL "https://api.github.com/repos/cloudflare/cloudflared/releases/latest" | grep '"tag_name":' | cut -d'"' -f4 | sed 's/^v//')
  
  if [ "$(normalize_version "$current_cloudflared")" != "$(normalize_version "$latest_cloudflared")" ]; then
    warning "Cloudflared 有新版本可用: $latest_cloudflared (当前: $current_cloudflared)"
  else
    success "Cloudflared 已是最新版本: $current_cloudflared"
  fi
else
  warning "Cloudflared 未安装"
fi

echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

# 保持原有菜单逻辑
info "🎉 检查完成"
info "📌 可能需要重启服务使更改生效"
info "▶ systemctl restart xray.service"
info "▶ systemctl restart hysteria.service"
info "▶ systemctl restart cloudflared.service"

echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

# 修复退出问题 - 添加等待输入
read -p "$(echo -e "${cyan}按回车键返回主菜单...${reset}")" 
bash /root/VPN/menu/install_upgrade.sh
