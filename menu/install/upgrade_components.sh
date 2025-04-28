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

echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "${orange}                                  🔄 功能升级更新${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

# 检查VPN目录是否存在
info "📁 检查 /root/VPN 目录..."
if [ ! -d "/root/VPN" ]; then
  error_exit "❌ /root/VPN 目录不存在，请先运行安装脚本"
else
  success "/root/VPN 目录存在"
fi

cd /root/VPN || error_exit "无法进入 /root/VPN"

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
