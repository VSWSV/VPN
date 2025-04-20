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

function error() {
  echo -e "${red}❌ $1${reset}"
}

# 计算标题居中
title="🔎 安装完整性验证"
title_length=${#title}
total_width=83
padding=$(( (total_width - title_length) / 2 ))

echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
printf "%${padding}s" ""; echo -e "${orange}$title${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

# 1. 验证组件版本
info "🔄 验证组件版本..."
components=(
  "Xray|xray/xray version|Xray-core"
  "Hysteria|HY2/hysteria version|v"
  "Cloudflared|cloudflared --version|cloudflared"
)



for comp in "${components[@]}"; do
  IFS='|' read -r name cmd pattern <<< "$comp"
  if [ -f "/root/VPN/${cmd%% *}" ]; then
    version=$($cmd 2>&1 | head -n 1)
    if [[ "$version" == *"$pattern"* ]]; then
      success "$name 版本正常: ${green}$(echo $version | head -n 1)${reset}"
    else
      error "$name 版本异常: ${red}$version${reset}"
    fi
  else
    error "$name 可执行文件不存在"
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
  "xray|Xray 服务"
  "hysteria|Hysteria 服务"
  "cloudflared|Cloudflared 服务"
)

active_services=0
for svc in "${services[@]}"; do
  IFS='|' read -r service name <<< "$svc"
  if systemctl is-active --quiet "$service"; then
    success "$name 正在运行"
    ((active_services++))
  else
    error "$name 未运行"
  fi
done

# 4. 验证配置文件
info "📄 验证配置文件..."
configs=(
  "/root/VPN/VLESS/config.json|VLESS 配置文件"
  "/root/VPN/HY2/hysteria.yaml|HY2  配置文件"
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
  "https://www.google.com|Google"
  "https://www.cloudflare.com|Cloudflare"
  "https://github.com|GitHub"
)

reachable=0
for url in "${test_urls[@]}"; do
  IFS='|' read -r address name <<< "$url"
  if curl --max-time 5 -s -o /dev/null "$address"; then
    success "$name 可达"
    ((reachable++))
  else
    warning "$name 不可达"
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
