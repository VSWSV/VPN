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
title="🔍 系统依赖检查"
title_length=${#title}
total_width=83
padding=$(( (total_width - title_length) / 2 ))

echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
printf "%${padding}s" ""; echo -e "${orange}$title${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

# 1. 检查目录结构
info "📂 检查目录结构..."
[ -d "/root/VPN" ] && success "/root/VPN 目录存在" || error "/root/VPN 目录不存在"
[ -d "/root/VPN/xray" ] && success "/root/VPN/xray 目录存在" || error "/root/VPN/xray 目录不存在"
[ -f "/root/VPN/xray/xray" ] && success "Xray 可执行文件存在" || error "Xray 可执行文件缺失"
[ -f "/root/VPN/hysteria" ] && success "Hysteria 可执行文件存在" || error "Hysteria 可执行文件缺失"
[ -f "/root/VPN/cloudflared" ] && success "Cloudflared 可执行文件存在" || error "Cloudflared 可执行文件缺失"

# 2. 检查基本依赖
info "📦 检查基本依赖..."
dependencies=("curl" "wget" "unzip" "socat" "tar" "sudo" "git" "mtr-tiny" "traceroute" "bmon")
missing_deps=0

for dep in "${dependencies[@]}"; do
  if command -v "$dep" &> /dev/null; then
    success "$dep 已安装"
  else
    error "$dep 未安装"
    ((missing_deps++))
  fi
done

# 3. 检查配置文件
info "📄 检查配置文件..."
config_files=(
  "/root/VPN/xray/config.json"
  "/root/VPN/hysteria.yaml"
  "/root/VPN/.cloudflared/config.yml"
  "/root/VPN/.cloudflared/cert.pem"
)

missing_configs=0
for config in "${config_files[@]}"; do
  if [ -f "$config" ]; then
    success "$config 存在"
  else
    warning "$config 缺失"
    ((missing_configs++))
  fi
done

# 4. 检查服务状态
info "⚙️ 检查服务状态..."
services=("xray" "hysteria" "cloudflared")
running_services=0

for service in "${services[@]}"; do
  if systemctl is-active --quiet "$service"; then
    success "$service 服务正在运行"
    ((running_services++))
  else
    warning "$service 服务未运行"
  fi
done

# 5. 检查执行权限
info "🔒 检查执行权限..."
executables=(
  "/root/VPN/xray/xray"
  "/root/VPN/hysteria"
  "/root/VPN/cloudflared"
)

for exe in "${executables[@]}"; do
  if [ -x "$exe" ]; then
    success "$exe 有执行权限"
  else
    error "$exe 缺少执行权限"
  fi
done

# 总结报告
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
info "📊 检查总结:"
[ $missing_deps -eq 0 ] && success "所有依赖已安装" || warning "缺少 $missing_deps 个依赖"
[ $missing_configs -eq 0 ] && success "所有配置文件存在" || warning "缺少 $missing_configs 个配置文件"
[ $running_services -eq ${#services[@]} ] && success "所有服务正在运行" || warning "$running_services/${#services[@]} 个服务在运行"

echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
info "💡 建议操作:"
[ $missing_deps -gt 0 ] && echo -e "${yellow}▶ 运行安装脚本安装缺失依赖${reset}"
[ $missing_configs -gt 0 ] && echo -e "${yellow}▶ 检查并创建缺失的配置文件${reset}"
[ $running_services -lt ${#services[@]} ] && echo -e "${yellow}▶ 启动未运行的服务 (systemctl start <服务名>)${reset}"

echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

# 返回上级菜单
read -p "$(echo -e "${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/install_upgrade.sh
