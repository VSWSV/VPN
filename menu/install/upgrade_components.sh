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

# 版本规范化函数
function normalize_version() {
  echo "$1" | sed 's/^v//;s/[^0-9.]//g'
}

# 计算标题居中
title="🔄 高级组件更新工具"
title_length=${#title}
total_width=83
padding=$(( (total_width - title_length) / 2 ))

echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
printf "%${padding}s" ""; echo -e "${orange}$title${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

# 检查VPN目录
info "📁 检查 /root/VPN 目录..."
[ -d "/root/VPN" ] || error_exit "❌ /root/VPN 目录不存在"
success "/root/VPN 目录存在"
cd /root/VPN || error_exit "无法进入 /root/VPN"

# 获取最新版本函数
function get_latest_xray() {
  curl -sL "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep '"tag_name":' | cut -d'"' -f4
}

function get_latest_hysteria() {
  curl -sL "https://api.github.com/repos/apernet/hysteria/releases/latest" | grep '"tag_name":' | cut -d'"' -f4
}

function get_latest_cloudflared() {
  curl -sL "https://api.github.com/repos/cloudflare/cloudflared/releases/latest" | grep '"tag_name":' | cut -d'"' -f4
}

# 更新Xray函数
function update_xray() {
  latest=$1
  info "正在下载 Xray ${latest}..."
  arch=$(uname -m)
  case $arch in
    x86_64) arch="64" ;;
    aarch64) arch="arm64-v8a" ;;
    *) error_exit "不支持的架构: $arch" ;;
  esac
  
  tmp_file="/tmp/xray-linux-${arch}.zip"
  curl -L "https://github.com/XTLS/Xray-core/releases/download/${latest}/Xray-linux-${arch}.zip" -o "$tmp_file" || return 1
  unzip -o "$tmp_file" xray -d /root/VPN/xray/ || return 1
  rm "$tmp_file"
  chmod +x /root/VPN/xray/xray
  return 0
}

# 更新Hysteria函数
function update_hysteria() {
  latest=$1
  info "正在下载 Hysteria ${latest}..."
  arch=$(uname -m)
  case $arch in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *) error_exit "不支持的架构: $arch" ;;
  esac
  
  tmp_file="/tmp/hysteria-linux-${arch}"
  curl -L "https://github.com/apernet/hysteria/releases/download/${latest}/hysteria-linux-${arch}" -o "$tmp_file" || return 1
  mv "$tmp_file" /root/VPN/hysteria
  chmod +x /root/VPN/hysteria
  return 0
}

# 更新Cloudflared函数
function update_cloudflared() {
  latest=$1
  info "正在下载 Cloudflared ${latest}..."
  arch=$(uname -m)
  case $arch in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *) error_exit "不支持的架构: $arch" ;;
  esac
  
  tmp_file="/tmp/cloudflared"
  curl -L "https://github.com/cloudflare/cloudflared/releases/download/${latest}/cloudflared-linux-${arch}" -o "$tmp_file" || return 1
  mv "$tmp_file" /root/VPN/cloudflared
  chmod +x /root/VPN/cloudflared
  return 0
}

# 检查更新
info "🔄 检查组件更新..."
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

need_update=0
declare -A update_info

# Xray检查（修正版）
if [ -f "/root/VPN/xray/xray" ]; then
  current_xray=$(/root/VPN/xray/xray version | head -n 1 | awk '{print $2}')
  normalized_current=$(normalize_version "$current_xray")
  latest_xray=$(get_latest_xray)
  normalized_latest=$(normalize_version "$latest_xray")
  
  if [ "$normalized_current" != "$normalized_latest" ]; then
    echo -e "${yellow}║ Xray 有新版本可用: ${latest_xray} (当前: ${current_xray})${reset}"
    update_info["xray"]=$latest_xray
    need_update=1
  else
    echo -e "${green}║ Xray 已是最新版本: ${current_xray}${reset}"
  fi
else
  echo -e "${yellow}║ Xray 未安装${reset}"
fi

# Hysteria检查（修正版）
if [ -f "/root/VPN/hysteria" ]; then
  current_hysteria=$(/root/VPN/hysteria version | awk 'NR==1{print $3}' | tr -d '\n')
  normalized_current=$(normalize_version "$current_hysteria")
  latest_hysteria=$(get_latest_hysteria)
  normalized_latest=$(normalize_version "$latest_hysteria")
  
  if [ "$normalized_current" != "$normalized_latest" ]; then
    echo -e "${yellow}║ Hysteria 有新版本可用: ${latest_hysteria}${reset}"
    echo -e "${yellow}║ 当前版本: ${current_hysteria}${reset}"
    update_info["hysteria"]=$latest_hysteria
    need_update=1
  else
    echo -e "${green}║ Hysteria 已是最新版本: ${current_hysteria}${reset}"
  fi
else
  echo -e "${yellow}║ Hysteria 未安装${reset}"
fi

# Cloudflared检查
if [ -f "/root/VPN/cloudflared" ]; then
  current_cloudflared=$(/root/VPN/cloudflared version | grep -oP 'cloudflared version \K[\d.]+')
  normalized_current=$(normalize_version "$current_cloudflared")
  latest_cloudflared=$(get_latest_cloudflared | sed 's/^v//')
  normalized_latest=$(normalize_version "$latest_cloudflared")
  
  if [ "$normalized_current" != "$normalized_latest" ]; then
    echo -e "${yellow}║ Cloudflared 有新版本可用: ${latest_cloudflared} (当前: ${current_cloudflared})${reset}"
    update_info["cloudflared"]=$latest_cloudflared
    need_update=1
  else
    echo -e "${green}║ Cloudflared 已是最新版本: ${current_cloudflared}${reset}"
  fi
else
  echo -e "${yellow}║ Cloudflared 未安装${reset}"
fi

echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

# 自动更新逻辑
if [ $need_update -eq 1 ]; then
  echo -e "${orange}🔄 发现可用的组件更新${reset}"
  read -p "$(echo -e "${cyan}是否要自动更新所有可用组件? [y/N]: ${reset}")" confirm
  
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    for component in "${!update_info[@]}"; do
      case $component in
        xray)
          info "正在更新 Xray 到 ${update_info[xray]}..."
          if update_xray "${update_info[xray]}"; then
            success "Xray 更新成功"
          else
            warning "Xray 更新失败"
          fi
          ;;
        hysteria)
          info "正在更新 Hysteria 到 ${update_info[hysteria]}..."
          if update_hysteria "${update_info[hysteria]}"; then
            success "Hysteria 更新成功"
          else
            warning "Hysteria 更新失败"
          fi
          ;;
        cloudflared)
          info "正在更新 Cloudflared 到 ${update_info[cloudflared]}..."
          if update_cloudflared "${update_info[cloudflared]}"; then
            success "Cloudflared 更新成功"
          else
            warning "Cloudflared 更新失败"
          fi
          ;;
      esac
    done
    
    # 更新后验证
    info "🔄 验证更新结果..."
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    
    # Xray验证
    if [ -f "/root/VPN/xray/xray" ]; then
      new_version=$(/root/VPN/xray/xray version | head -n 1 | awk '{print $2}')
      echo -e "║ Xray 当前版本: ${green}${new_version}${reset}"
    fi
    
    # Hysteria验证
    if [ -f "/root/VPN/hysteria" ]; then
      new_version=$(/root/VPN/hysteria version | awk 'NR==1{print $3}' | tr -d '\n')
      echo -e "║ Hysteria 当前版本: ${green}${new_version}${reset}"
    fi
    
    # Cloudflared验证
    if [ -f "/root/VPN/cloudflared" ]; then
      new_version=$(/root/VPN/cloudflared version | grep -oP 'cloudflared version \K[\d.]+')
      echo -e "║ Cloudflared 当前版本: ${green}${new_version}${reset}"
    fi
    
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    
    # 重启服务
    info "重启服务以应用更新..."
    systemctl restart xray.service 2>/dev/null && echo -e "║ Xray 服务重启 ${green}成功${reset}" || echo -e "║ Xray 服务重启 ${red}失败${reset}"
    systemctl restart hysteria.service 2>/dev/null && echo -e "║ Hysteria 服务重启 ${green}成功${reset}" || echo -e "║ Hysteria 服务重启 ${red}失败${reset}"
    systemctl restart cloudflared.service 2>/dev/null && echo -e "║ Cloudflared 服务重启 ${green}成功${reset}" || echo -e "║ Cloudflared 服务重启 ${red}失败${reset}"
    
  else
    info "已跳过组件自动更新"
  fi
fi

# 项目代码更新
info "🔄 从GitHub更新VPN项目..."
if ! command -v git &> /dev/null; then
  info "安装git..."
  apt update && apt install -y git || error_exit "Git安装失败"
fi

if [ ! -d "/root/VPN/.git" ]; then
  info "首次克隆项目..."
  mv /root/VPN /root/VPN_backup
  git clone https://github.com/VSWSV/VPN.git /root/VPN || error_exit "项目克隆失败"
  cp -r /root/VPN_backup/* /root/VPN/
  rm -rf /root/VPN_backup
else
  info "更新现有项目..."
  git fetch origin && git reset --hard origin/main || error_exit "项目更新失败"
fi

# 显示更新信息
latest_commit=$(git log -1 --pretty=format:"%h - %s (%ci)")
changed_files=$(git diff --name-only HEAD~1 HEAD)
success "项目更新成功"
info "📝 最后提交: ${green}$latest_commit${reset}"
info "📄 更改的文件: ${green}$changed_files${reset}"

# 权限设置
info "🔄 更新组件权限..."
[ -f "/root/VPN/xray/xray" ] && chmod +x "/root/VPN/xray/xray" && info "设置执行权限: Xray"
[ -f "/root/VPN/hysteria" ] && chmod +x "/root/VPN/hysteria" && info "设置执行权限: Hysteria"
[ -f "/root/VPN/cloudflared" ] && chmod +x "/root/VPN/cloudflared" && info "设置执行权限: Cloudflared"

info "🔒 设置目录权限..."
find /root/VPN -name "*.sh" -exec chmod +x {} \;
chmod -R 755 /root/VPN
success "权限设置完成"

echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
info "🎉 升级完成"
echo -e "${yellow}📌 可能需要重启服务使更改生效${reset}"
echo -e "${yellow}▶ systemctl restart xray.service${reset}"
echo -e "${yellow}▶ systemctl restart hysteria.service${reset}"
echo -e "${yellow}▶ systemctl restart cloudflared.service${reset}"
echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

# 返回菜单
read -p "$(echo -e "${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/install_upgrade.sh
