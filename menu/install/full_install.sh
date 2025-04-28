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

# 下载安装函数
install_global_link() {
  local binary_path=$1
  local global_name=$2

  if [ -f "$binary_path" ]; then
    ln -sf "$binary_path" "/usr/local/bin/$global_name"
    chmod +x "/usr/local/bin/$global_name"
    success "$global_name 已创建全局命令: /usr/local/bin/$global_name"
  else
    warning "$global_name 未找到实际路径, 忽略全局链接"
  fi
}

# 下载函数
download_component() {
  local name=$1
  local url=$2
  local filename=$3
  local is_zip=$4
  local binary_name=$5
  local install_path="/root/VPN"

  if [ "$name" = "Xray" ]; then
    local binary_path="$install_path/xray/xray"
    local target_path="$install_path/xray"
  else
    local binary_path="$install_path/$binary_name"
    local target_path="$install_path"
  fi

  if [ -x "$binary_path" ]; then
    warning "$name 已存在于: $binary_path，是否覆盖安装？(y/n)"
    read -r choice
    if [[ "$choice" != [yY] ]]; then
      return 1
    fi
    rm -f "$binary_path"
  fi

  info "开始下载 $name..."
  if ! wget -O "$install_path/$filename" "$url"; then
    warning "$name 下载失败"
    return 1
  fi

  if [ "$is_zip" = "true" ]; then
    if ! unzip -o "$install_path/$filename" -d "$target_path"; then
      warning "$name 解压失败"
      return 1
    fi
    rm "$install_path/$filename"
  fi

  chmod +x "$binary_path" 2>/dev/null

  if [ -x "$binary_path" ]; then
    success "$name 安装成功: $binary_path"
    install_global_link "$binary_path" "$binary_name"
    return 0
  else
    warning "$name 安装验证失败"
    return 1
  fi
}

echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "${orange}                 🛠️ 正在开始一键环境安装（含所有依赖）${reset}"
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
apt update && apt install -y curl wget unzip socat tar sudo jq openssl \
  software-properties-common mtr-tiny traceroute bmon \
  && success "工具安装完成" || error_exit "工具安装失败"

# 启用Universe源
info "🔓 启用Universe源..."
add-apt-repository universe -y && apt update \
  && success "源启用成功" || warning "源启用失败"

# 安装组件
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
info "⬇️ 正在安装组件..."

# Xray
download_component "Xray" \
  "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip" \
  "Xray-linux-64.zip" "true" "xray"

# Hysteria
download_component "Hysteria" \
  "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64" \
  "hysteria" "false" "hysteria"

# Cloudflared
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
echo -e "${yellow}▶ Xray:        xray run -config /root/VPN/config.json${reset}"
echo -e "${yellow}▶ Hysteria:    hysteria --config /root/VPN/hysteria.yaml${reset}"
echo -e "${yellow}▶ Cloudflared: cloudflared tunnel login${reset}"
echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

read -p "$(echo -e ${cyan}按回车键返回...${reset})" dummy
bash /root/VPN/menu/install_upgrade.sh
