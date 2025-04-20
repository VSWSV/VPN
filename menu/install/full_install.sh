#!/bin/bash
clear

# 颜色定义
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
cyan="\033[1;36m"
orange="\033[38;5;208m"
reset="\033[0m"

# 输出函数
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

# 组件检测函数
check_component() {
  local name=$1
  local binary_path=$2
  
  if [ -x "$binary_path" ]; then
    success "$name 已安装: $binary_path"
    return 0
  else
    warning "$name 未找到: $binary_path"
    return 1
  fi
}

# 增强版下载函数
download_component() {
  local name=$1
  local url=$2
  local filename=$3
  local is_zip=$4
  local binary_name=$5
  local install_path="/root/VPN"

  # 特殊处理Xray路径
  if [ "$name" = "Xray" ]; then
    local binary_path="$install_path/xray/xray"
    local target_path="$install_path/xray"
  else
    local binary_path="$install_path/$binary_name"
    local target_path="$install_path"
  fi

  # 检查是否已安装
  if [ -x "$binary_path" ]; then
    warning "$name 已存在于: $binary_path，是否覆盖安装？(y/n)"
    read -r choice
    if [[ "$choice" != [yY] ]]; then
      return 1
    fi
    rm -f "$binary_path"
  fi

  # 下载文件
  info "开始下载 $name..."
  if ! wget -O "$install_path/$filename" "$url"; then
    warning "$name 下载失败"
    return 1
  fi

  # 处理压缩包
  if [ "$is_zip" = "true" ]; then
    if ! unzip -o "$install_path/$filename" -d "$target_path"; then
      warning "$name 解压失败"
      return 1
    fi
    rm "$install_path/$filename"
  fi

  # 设置权限
  chmod +x "$binary_path" 2>/dev/null

  # 验证安装
  if [ -x "$binary_path" ]; then
    success "$name 安装成功: $binary_path"
    return 0
  else
    warning "$name 安装验证失败"
    return 1
  fi
}

# 主标题
title="🛠️ 正在开始一键环境安装（含所有依赖）"
title_length=${#title}
total_width=83
padding=$(( (total_width - title_length) / 2 ))

echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
printf "%${padding}s" ""; echo -e "${orange}$title${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

# 检查VPN目录
info "📁 检查 /root/VPN 目录..."
if [ ! -d "/root/VPN" ]; then
  mkdir -p /root/VPN || error_exit "创建目录失败"
  chmod 755 /root/VPN
  success "已创建 /root/VPN"
else
  success "/root/VPN 已存在"
fi

cd /root/VPN || error_exit "无法进入目录"

# 安装基础工具
info "🔧 安装基础工具..."
apt update && apt install -y curl wget unzip socat tar sudo \
  software-properties-common mtr-tiny traceroute bmon \
  && success "工具安装完成" || error_exit "工具安装失败"

# 启用Universe源
info "🔓 启用Universe源..."
add-apt-repository universe -y && apt update \
  && success "源启用成功" || warning "源启用失败"

# 安装组件
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
info "⬇️ 正在安装组件..."

# Xray安装（特殊处理）
download_component "Xray" \
  "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" \
  "Xray-linux-64.zip" "true" "xray"

# Hysteria安装
download_component "Hysteria" \
  "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64" \
  "hysteria" "false" "hysteria"

# Cloudflared安装
download_component "Cloudflared" \
  "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" \
  "cloudflared" "false" "cloudflared"

# 验证安装
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
info "🔍 安装结果验证:"
check_component "Xray" "/root/VPN/xray/xray"
check_component "Hysteria" "/root/VPN/hysteria"
check_component "Cloudflared" "/root/VPN/cloudflared"

# 使用说明
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
info "🎉 安装完成！使用命令:"
echo -e "${yellow}▶ Xray:    /root/VPN/xray/xray run -config /root/VPN/config.json${reset}"
echo -e "${yellow}▶ Hysteria: /root/VPN/hysteria --config /root/VPN/hysteria.yaml${reset}"
echo -e "${yellow}▶ Cloudflared: /root/VPN/cloudflared tunnel login${reset}"
echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

# 返回菜单
read -p "$(echo -e "${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/install_upgrade.sh
