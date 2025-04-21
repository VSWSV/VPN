#!/bin/bash
clear

# 颜色定义
cyan="\033[1;36m"; green="\033[1;32m"; yellow="\033[1;33m"
red="\033[1;31m"; orange="\033[38;5;208m"; white="\033[1;37m"; reset="\033[0m"
lightpink="\033[38;5;213m"

# 路径配置
CLOUDFLARED_DIR="/root/.cloudflared"
CONFIG_FILE="$CLOUDFLARED_DIR/config.yml"
LOG_FILE="$CLOUDFLARED_DIR/tunnel.log"

# 校验配置文件
verify_config() {
    [ -f "$CONFIG_FILE" ] || { echo -e "${red}❌ 缺少 config.yml 配置文件"; return 1; }

    CREDENTIALS_FILE=$(grep '^credentials-file:' "$CONFIG_FILE" | awk '{print $2}')
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        echo -e "${red}❌ 缺少认证凭证文件: $CREDENTIALS_FILE"; return 1;
    fi

    grep -q '^tunnel:' "$CONFIG_FILE" || { echo -e "${red}❌ 配置中缺少 tunnel 字段"; return 1; }

    return 0
}

# 获取隧道 ID
get_tunnel_id() {
    grep '^tunnel:' "$CONFIG_FILE" | awk '{print $2}'
}

# 显示头部
header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${orange}                              🚀 启动 Cloudflare 隧道                           ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

# 显示底部
footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

info() { echo -e "${yellow}🔹 $1${reset}"; }
success() { echo -e "${lightpink}✅ $1${reset}"; }
error() { echo -e "${red}❌ $1${reset}"; }

# 配置提示
config_prompt() {
    while true; do
        echo -e "${yellow}是否要现在配置 Cloudflare 隧道？${reset}"
        echo -e "${green}[Y] 是${reset} ${red}[N] 否${reset}"
        read -p "请输入选择 (Y/N): " choice

        case $choice in
            [Yy]) bash /root/VPN/menu/config/config_tunnel.sh; return $? ;;
            [Nn]) return $? ;;
            *) echo -e "${red}无效输入，请重新选择${reset}" ;;
        esac
    done
}

# 启动流程
header

# 校验配置
if ! verify_config; then
    config_prompt
    if [ $? -ne 0 ]; then
        echo -e "${yellow}退出配置流程...${reset}"
        footer
        read -p "$(echo -e "${cyan}按任意键返回上级菜单...${reset}")" -n 1
        bash /root/VPN/menu/start_service.sh
        exit 0
    fi
fi

TUNNEL_ID=$(get_tunnel_id)

# 使用 systemctl 检查是否已运行
if systemctl is-active --quiet cloudflared; then
    echo -e "${yellow}⚠️ Cloudflared 服务已运行${reset}"
    echo -e "${lightpink}📌 使用命令查看日志：${green}tail -f $LOG_FILE${reset}"
    footer
    read -p "$(echo -e "${cyan}按任意键返回上级菜单...${reset}")" -n 1
    bash /root/VPN/menu/start_service.sh
    exit 0
fi

# 启动服务
info "正在通过 systemctl 启动隧道服务..."
systemctl restart cloudflared

# 检查启动是否成功
sleep 3
if systemctl is-active --quiet cloudflared; then
    success "Cloudflared 隧道服务启动成功！"
    echo -e "${lightpink}📌 日志路径：${green}$LOG_FILE${reset}"
    echo -e "${yellow}❗ 请等待 1~2 分钟以完成连接同步${reset}"
else
    error "隧道启动失败！"
    echo -e "${red}⚠️ 可能原因："
    echo -e "1. 配置错误或证书缺失"
    echo -e "2. Cloudflared 文件未设置可执行权限"
    echo -e "3. 网络不通或端口占用"
    echo -e "${lightpink}🔍 查看日志：${green}tail -n 20 $LOG_FILE${reset}"
fi

footer
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
