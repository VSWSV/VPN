#!/bin/bash
clear

# 颜色定义
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
cyan="\033[1;36m"
orange="\033[38;5;208m"
reset="\033[0m"

# 基础函数
function info() { echo -e "${cyan}🔹 $1${reset}"; }
function success() { echo -e "${green}✅ $1${reset}"; }
function warning() { echo -e "${yellow}⚠️  $1${reset}"; }
function error_exit() { echo -e "${red}❌ $1${reset}"; exit 1; }

# 版本规范化函数（增强版）
function normalize_version() {
  echo "$1" | sed 's/^v//;s/[^0-9.]//g;s/^app\///'
}

# 获取Hysteria版本（增强版）
function get_hysteria_version() {
  /root/VPN/hysteria version 2>/dev/null | awk '
    /^v[0-9]/ {print $1; exit}
    /Version:/ {print $2; exit}
    /^Hysteria [0-9]/ {print $2; exit}
  ' | tr -d '\n'
}

# 标题显示
title="🔄 高级组件更新工具"
title_length=${#title}
total_width=83
padding=$(( (total_width - title_length) / 2 ))

echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
printf "%${padding}s" ""; echo -e "${orange}$title${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

# 目录检查
info "📁 检查 /root/VPN 目录..."
[ -d "/root/VPN" ] || error_exit "❌ /root/VPN 目录不存在"
success "/root/VPN 目录存在"
cd /root/VPN || error_exit "无法进入 /root/VPN"

# 服务状态检查函数
function check_service() {
  local service=$1
  if systemctl is-enabled "$service" 2>/dev/null | grep -q enabled; then
    return 0
  else
    return 1
  fi
}

# 更新检查逻辑
info "🔄 检查组件更新..."
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

need_update=0
declare -A update_info

# Xray检查
if [ -f "/root/VPN/xray/xray" ]; then
  current_xray=$(/root/VPN/xray/xray version | head -n 1 | awk '{print $2}')
  normalized_current=$(normalize_version "$current_xray")
  latest_xray=$(curl -sL "https://api.github.com/repos/XTLS/Xray-core/releases/latest" | grep '"tag_name":' | cut -d'"' -f4)
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

# Hysteria检查（使用新版本获取函数）
if [ -f "/root/VPN/hysteria" ]; then
  current_hysteria=$(get_hysteria_version)
  normalized_current=$(normalize_version "$current_hysteria")
  latest_hysteria=$(curl -sL "https://api.github.com/repos/apernet/hysteria/releases/latest" | grep '"tag_name":' | cut -d'"' -f4)
  normalized_latest=$(normalize_version "$latest_hysteria")
  
  if [ -z "$current_hysteria" ]; then
    echo -e "${yellow}║ Hysteria 版本获取失败${reset}"
  elif [ "$normalized_current" != "$normalized_latest" ]; then
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
  latest_cloudflared=$(curl -sL "https://api.github.com/repos/cloudflare/cloudflared/releases/latest" | grep '"tag_name":' | cut -d'"' -f4 | sed 's/^v//')
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
          arch=$(uname -m)
          case $arch in
            x86_64) arch="64" ;;
            aarch64) arch="arm64-v8a" ;;
            *) error_exit "不支持的架构: $arch" ;;
          esac
          
          tmp_file="/tmp/xray-linux-${arch}.zip"
          curl -L "https://github.com/XTLS/Xray-core/releases/download/${update_info[xray]}/Xray-linux-${arch}.zip" -o "$tmp_file" || {
            warning "Xray 下载失败";
            continue;
          }
          unzip -o "$tmp_file" xray -d /root/VPN/xray/ || {
            warning "Xray 解压失败";
            rm "$tmp_file";
            continue;
          }
          rm "$tmp_file"
          chmod +x /root/VPN/xray/xray
          success "Xray 更新成功"
          ;;
          
        hysteria)
          info "正在更新 Hysteria 到 ${update_info[hysteria]}..."
          arch=$(uname -m)
          case $arch in
            x86_64) arch="amd64" ;;
            aarch64) arch="arm64" ;;
            *) error_exit "不支持的架构: $arch" ;;
          esac
          
          tmp_file="/tmp/hysteria-linux-${arch}"
          curl -L "https://github.com/apernet/hysteria/releases/download/${update_info[hysteria]}/hysteria-linux-${arch}" -o "$tmp_file" || {
            warning "Hysteria 下载失败";
            continue;
          }
          mv "$tmp_file" /root/VPN/hysteria || {
            warning "Hysteria 移动失败";
            continue;
          }
          chmod +x /root/VPN/hysteria
          success "Hysteria 更新成功"
          ;;
          
        cloudflared)
          info "正在更新 Cloudflared 到 ${update_info[cloudflared]}..."
          arch=$(uname -m)
          case $arch in
            x86_64) arch="amd64" ;;
            aarch64) arch="arm64" ;;
            *) error_exit "不支持的架构: $arch" ;;
          esac
          
          tmp_file="/tmp/cloudflared"
          curl -L "https://github.com/cloudflare/cloudflared/releases/download/${update_info[cloudflared]}/cloudflared-linux-${arch}" -o "$tmp_file" || {
            warning "Cloudflared 下载失败";
            continue;
          }
          mv "$tmp_file" /root/VPN/cloudflared || {
            warning "Cloudflared 移动失败";
            continue;
          }
          chmod +x /root/VPN/cloudflared
          success "Cloudflared 更新成功"
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
    
    # Hysteria验证（使用新函数）
    if [ -f "/root/VPN/hysteria" ]; then
      new_version=$(get_hysteria_version)
      if [ -z "$new_version" ]; then
        echo -e "║ Hysteria 版本获取失败，请手动检查: ${red}/root/VPN/hysteria version${reset}"
      else
        echo -e "║ Hysteria 当前版本: ${green}${new_version}${reset}"
      fi
    fi
    
    # Cloudflared验证
    if [ -f "/root/VPN/cloudflared" ]; then
      new_version=$(/root/VPN/cloudflared version | grep -oP 'cloudflared version \K[\d.]+')
      echo -e "║ Cloudflared 当前版本: ${green}${new_version}${reset}"
    fi
    
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    
    # 增强的服务重启逻辑
    info "重启服务以应用更新..."
    for service in xray hysteria cloudflared; do
      if check_service "${service}.service"; then
        systemctl restart "${service}.service" && \
          echo -e "║ ${service} 服务重启 ${green}成功${reset}" || \
          echo -e "║ ${service} 服务重启 ${red}失败${reset} (请手动执行: systemctl restart ${service}.service)"
      else
        echo -e "║ ${service} 服务 ${yellow}未安装${reset} (请检查服务状态)"
      fi
    done
    
  else
    info "已跳过组件自动更新"
  fi
fi

# 其余部分保持不变...
