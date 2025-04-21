#!/bin/bash 
clear

# 颜色定义
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
  echo -e "${yellow}⚠️ $1${reset}"
}

function error() {
  echo -e "${red}❌ $1${reset}"
}

# 标题居中显示
title="🔎 安装完整性验证"
title_length=${#title}
total_width=83
padding=$(( (total_width - title_length) / 2 ))

echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
printf "%${padding}s" ""; echo -e "${orange}$title${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

# 1. 验证组件版本
components=(
  "Xray|/root/VPN/xray/xray version|Xray"
  "Hysteria|/root/VPN/hysteria version|Version:"
  "Cloudflared|/root/VPN/cloudflared --version|cloudflared"
)

for comp in "${components[@]}"; do
  IFS='|' read -r name cmd pattern <<< "$comp"
  check_path="${cmd%% *}"
  if [ -f "$check_path" ]; then
    version_output=$($cmd 2>&1 | grep -i "$pattern" | head -n 1)
    if [[ -n "$version_output" ]]; then
      success "$name 版本正常: ${green}$(echo "$version_output" | awk '{$1=$1;print}')${reset}"
    else
      warning "$name 无法识别版本信息"
      echo -e "${red}↳ 输出: $($cmd 2>&1 | head -n 2)${reset}"
    fi
  else
    error "$name 可执行文件不存在"
  fi
  
  # 新增: 检查是否已设置全局路径
  global_path="/usr/local/bin/${name,,}"
  if command -v "$global_path" &>/dev/null; then
    success "$name 已设置全局命令 ($global_path)"
  else
    warning "$name 未设置全局命令"
  fi

done

# 2. 验证端口监听
info "📡 验证端口监听..."
ports=("80" "443" "8443")
listening_ports=0

for port in "${ports[@]}"; do
  if ss -tulnp | grep -q ":$port"; then
    success "端口 $port 正在监听"
    ((listening_ports++))
  else
    warning "端口 $port 未监听"
  fi
done

# 3. 验证服务状态
info "⚙️ 验证服务状态..."

services=(
  "xray|Xray 服务|/root/VPN/xray/xray"
  "hysteria|Hysteria 服务|/root/VPN/hysteria"
  "cloudflared|Cloudflared 服务|/root/VPN/cloudflared"
)

active_services=0

for svc in "${services[@]}"; do
  IFS='|' read -r service name binary_path <<< "$svc"

  # 使用 pgrep 检查进程是否存在
  if pgrep -f "$binary_path" > /dev/null; then
    success "$name 正在运行 (手动或后台进程)"
    ((active_services++))
  else
    error "$name 未运行 (未发现进程)"
  fi
done

info "📄 验证配置文件..."
configs=(
  "/root/VPN/VLESS/config/vless.json|VLESS 配置文件"
  "/root/VPN/HY2/config/hysteria.yaml|HY2  配置文件"
  "/root/.cloudflared/config.yml|Cloudflared 配置文件"
  "/root/.cloudflared/cert.pem|Cloudflared 证书"
)

valid_configs=0
for cfg in "${configs[@]}"; do
  IFS='|' read -r file name <<< "$cfg"
  if [ -f "$file" ]; then
    if [ -s "$file" ]; then
      success "$name 存在且非空"
      ((valid_configs++))
    else
      warning "$name 存在但为空"
    fi
  else
    error "$name 不存在"
  fi
done

# 5. 验证网络连通性
info "🌐 验证网络连通性..."

test_urls=(
  "https://www.baidu.com|百度"
  "https://www.google.com|谷歌"
  "https://www.youtube.com|油管"
  "https://github.com|G 站" 
  "https://www.cloudflare.com|C  F" 
)

reachable=0
for entry in "${test_urls[@]}"; do
  IFS='|' read -r url name <<< "$entry"
  response=$(curl -o /dev/null -s -w "%{http_code} %{time_total}" --max-time 5 "$url")
  http_code=$(echo "$response" | awk '{print $1}')
  time_taken=$(echo "$response" | awk '{print $2}')
  
  if [[ "$http_code" =~ ^2|3 ]]; then
    success "$name 可访问 ($url) | 状态码: $http_code | 延迟: ${time_taken}s"
    ((reachable++))
  else
    warning "$name 访问失败 ($url) | 状态码: $http_code | 延迟: ${time_taken}s"
  fi
done

# 总结报告
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
info "📊 验证总结:"
[ $listening_ports -eq ${#ports[@]} ] && success "所有必要端口正在监听" || warning "$listening_ports/${#ports[@]} 个端口在监听"
[ $active_services -eq ${#services[@]} ] && success "所有服务正在运行" || warning "$active_services/${#services[@]} 个服务在运行"
[ $valid_configs -eq ${#configs[@]} ] && success "所有配置文件有效" || warning "$valid_configs/${#configs[@]} 个配置文件有效"
[ $reachable -eq ${#test_urls[@]} ] && success "所有测试网站可达" || warning "$reachable/${#test_urls[@]} 个测试网站可达"

echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
info "💡 建议操作:"
[ $listening_ports -lt ${#ports[@]} ] && echo -e "${yellow}▶ 检查端口监听问题 (netstat -tulnp)${reset}"
[ $active_services -lt ${#services[@]} ] && echo -e "${yellow}▶ 启动未运行的服务 (systemctl start <服务名>)${reset}"
[ $valid_configs -lt ${#configs[@]} ] && echo -e "${yellow}▶ 检查缺失或空的配置文件${reset}"
[ $reachable -lt ${#test_urls[@]} ] && echo -e "${yellow}▶ 检查网络连接和DNS设置${reset}"

echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

# 返回上级菜单
read -p "$(echo -e "${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/install_upgrade.sh
