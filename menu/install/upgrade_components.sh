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
  "VLESS/config/vless.json"
  "HY2/config/hysteria.yaml"
  "../.cloudflared/config.yml"
  "../.cloudflared/cert.pem"
)

backup_count=0
for config in "${config_files[@]}"; do
  config_path="/root/VPN/$config"
  if [[ $config == ../* ]]; then
    config_path="/root/${config#../}"
  fi
  
  if [ -f "$config_path" ]; then
    mkdir -p "$backup_dir/$(dirname "$config")"
    cp "$config_path" "$backup_dir/$config"
    info "✅ 已备份: $config_path"
    ((backup_count++))
  else
    warning "⚠️  配置文件不存在: $config_path"
  fi
done

if [ $backup_count -gt 0 ]; then
  success "已备份 $backup_count 个配置文件到: $backup_dir"
else
  warning "未找到任何可备份的配置文件"
fi

# 从GitHub更新项目
info "🔄 从GitHub更新项目..."
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

# 获取最后一次提交信息
latest_commit=$(git log -1 --pretty=format:"%h - %s (%ci)")
changed_files=$(git diff --name-only HEAD~1 HEAD)
success "项目更新成功"
info "📝 最后提交: ${green}$latest_commit${reset}"
info "📄 更改的文件: ${green}$changed_files${reset}"

# 恢复配置文件
info "🔄 恢复配置文件..."
for config in "${config_files[@]}"; do
  backup_path="$backup_dir/$config"
  restore_path="/root/VPN/$config"
  if [[ $config == ../* ]]; then
    restore_path="/root/${config#../}"
  fi
  
  if [ -f "$backup_path" ]; then
    mkdir -p "$(dirname "$restore_path")"
    cp "$backup_path" "$restore_path"
    info "已恢复: $restore_path"
  fi
done
success "配置文件恢复完成"

# 更新组件权限
info "🔄 更新组件权限..."
components=(
  "/root/VPN/xray/xray"
  "/root/VPN/hysteria"
  "/root/VPN/cloudflared"
)

for comp in "${components[@]}"; do
  if [ -f "$comp" ]; then
    chmod +x "$comp"
    info "设置执行权限: $comp"
  else
    warning "组件不存在: $comp"
  fi
done

# 设置目录权限
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

# 返回上级菜单
read -p "$(echo -e "${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/install_upgrade.sh
