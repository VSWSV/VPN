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
info "📁 检查 /root/VPN 目录..."
if [ ! -d "/root/VPN" ]; then
  error_exit "❌ /root/VPN 目录不存在，请先运行安装脚本"
else
  success "/root/VPN 目录存在"
fi

cd /root/VPN || error_exit "无法进入 /root/VPN"

# 备份配置文件
info "📦 备份配置文件..."
backup_dir="/root/VPN/backup_$(date +%Y%m%d%H%M%S)"
mkdir -p "$backup_dir"

# 备份重要配置文件
config_files=(
  "xray/config.json"
  "hysteria.yaml"
  ".cloudflared/config.yml"
  ".cloudflared/cert.pem"
)

for config in "${config_files[@]}"; do
  if [ -f "$config" ]; then
    mkdir -p "$backup_dir/$(dirname "$config")"
    cp "$config" "$backup_dir/$config"
    info "已备份: $config"
  fi
done
success "配置文件备份完成，保存在: $backup_dir"

# 从GitHub更新项目
info "🔄 从GitHub更新项目..."
if ! command -v git &> /dev/null; then
  info "安装git..."
  apt install -y git || error_exit "Git安装失败"
fi

if [ ! -d "/root/VPN/.git" ]; then
  git clone https://github.com/VSWSV/VPN.git /root/VPN-temp && \
  cp -r /root/VPN-temp/. /root/VPN/ && \
  rm -rf /root/VPN-temp || error_exit "项目克隆失败"
else
  git fetch origin && git reset --hard origin/main || error_exit "项目更新失败"
fi

# 获取最后一次提交信息
latest_commit=$(git log -1 --pretty=format:"%h - %s (%ci)")
changed_files=$(git diff --name-only HEAD~1 HEAD)
success "项目更新成功"
info "📝 最后提交: ${green}$latest_commit${reset}"
info "📄 更改的文件:"
echo -e "${yellow}$changed_files${reset}"

# 恢复配置文件
info "🔄 恢复配置文件..."
for config in "${config_files[@]}"; do
  if [ -f "$backup_dir/$config" ]; then
    mkdir -p "$(dirname "$config")"
    cp "$backup_dir/$config" "$config"
    info "已恢复: $config"
  fi
done
success "配置文件恢复完成"

# 更新组件
info "🔄 更新组件..."
components=(
  "xray/xray"
  "hysteria"
  "cloudflared"
)

for comp in "${components[@]}"; do
  if [ -f "$comp" ]; then
    chmod +x "$comp"
    info "设置执行权限: $comp"
  fi
done

# 设置最高权限
info "🔒 设置最高执行权限..."
chmod -R 755 /root/VPN
chmod +x /root/VPN/*.sh
success "权限设置完成"

echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
info "🎉 升级完成"
echo -e "${yellow}📌 可能需要重启服务使更改生效${reset}"
echo -e "${yellow}▶ systemctl restart xray.service${reset}"
echo -e "${yellow}▶ systemctl restart hysteria.service${reset}"
echo -e "${yellow}▶ systemctl restart cloudflared.service${reset}"
echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
