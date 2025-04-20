#!/bin/bash

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
function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${orange}                              🚀 启动 Cloudflare 隧道                           ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

# 显示底部
function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 提示
info() { echo -e "${yellow}🔹 $1${reset}"; }
success() { echo -e "${lightpink}✅ $1${reset}"; }
error() { echo -e "${red}❌ $1${reset}"; }

config_prompt() {
    while true; do
        echo -e "${yellow}是否要现在配置 Cloudflare 隧道？${reset}"
        echo -e "${green}[Y] 是${reset} ${red}[N] 否${reset}"
        read -p "请输入选择 (Y/N): " choice

        case $choice in
            [Yy])
                bash /root/VPN/menu/config/config_tunnel.sh
                return $?
                ;;
            [Nn])
                bash /root/VPN/menu/start_service.sh
                return $?
                ;;
            *)
                echo -e "${red}无效输入，请重新选择${reset}"
                ;;
        esac
    done
}

# 主逻辑
clear
header

if ! verify_config; then
    config_prompt
    exit $?
fi

TUNNEL_ID=$(get_tunnel_id)

if pgrep -f "cloudflared tunnel run" >/dev/null; then
    PID=$(pgrep -f "cloudflared tunnel run")
    echo -e "${yellow}⚠️ 隧道已在运行中 (PID: ${green}$PID${yellow})${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${lightpink}📌 使用命令查看日志: ${green}tail -f $LOG_FILE${reset}"
    footer
    read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
    bash /root/VPN/menu/start_service.sh
fi

info "正在启动隧道: ${green}$TUNNEL_ID${reset}"
nohup cloudflared tunnel run > "$LOG_FILE" 2>&1 &
sleep 2

if pgrep -f "cloudflared tunnel run" >/dev/null; then
    PID=$(pgrep -f "cloudflared tunnel run")
    success "隧道启动成功! (PID: ${green}$PID${reset})"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${lightpink}📌 实时日志路径: ${green}$LOG_FILE${reset}"
else
    error "隧道启动失败!"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${red}⚠️ 可能原因:"
    echo -e "1. 证书未正确配置"
    echo -e "2. 配置文件错误或缺失字段"
    echo -e "3. cloudflared 程序不可执行"
    echo -e "4. 网络连接问题${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${lightpink}🔍 查看错误详情: ${green}tail -n 20 $LOG_FILE${reset}"
fi
footer
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
