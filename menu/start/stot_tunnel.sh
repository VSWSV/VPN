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

    # 提取端口信息
    PORT=$(grep -A5 'ingress:' "$CONFIG_FILE" | grep -E 'http://[^:]+:([0-9]+)' | sed -E 's|.*:([0-9]+).*|\1|' | head -1)
    [ -z "$PORT" ] && PORT="未配置"

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

# 杀掉已有隧道进程
kill_tunnel() {
    pkill -f "cloudflared tunnel run" && sleep 1
    if pgrep -f "cloudflared tunnel run" >/dev/null; then
        pkill -9 -f "cloudflared tunnel run"
    fi
}

# 主逻辑开始
header

# 检查配置
if ! verify_config; then
    echo -e "${yellow}⚠️ 检测配置失败，请检查配置文件${reset}"
    footer
    read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
    bash /root/VPN/menu/start_service.sh
    exit 1
fi

# 获取隧道 ID 和端口
TUNNEL_ID=$(get_tunnel_id)
PORT=$(grep -A5 'ingress:' "$CONFIG_FILE" | grep -E 'http://[^:]+:([0-9]+)' | sed -E 's|.*:([0-9]+).*|\1|' | head -1)
[ -z "$PORT" ] && PORT="未配置"

# ✅ 检查是否已有运行中的进程
if pgrep -f "cloudflared tunnel run" >/dev/null; then
    PID=$(pgrep -f "cloudflared tunnel run")
    echo -e "${yellow}⚠️ 隧道已在运行中 (主进程 PID: ${green}$PID${yellow})${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}📌 隧道信息:"
    echo -e "  🔵 本地端口: ${lightpink}$PORT${reset}"
    echo -e "  🆔 隧道 ID: ${lightpink}$TUNNEL_ID${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${lightpink}📌 使用命令查看日志: ${green}tail -f $LOG_FILE${reset}"
    footer
    read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
    bash /root/VPN/menu/start_service.sh
    exit 0
fi

# 没有运行才执行清理（防止错误重启）
kill_tunnel >/dev/null 2>&1

# 启动服务
info "正在启动隧道: ${green}$TUNNEL_ID${reset}"
nohup cloudflared tunnel run > "$LOG_FILE" 2>&1 &

sleep 5

# 启动后再次检测是否成功
if pgrep -f "cloudflared tunnel run" >/dev/null; then
    PID=$(pgrep -f "cloudflared tunnel run")
    success "隧道启动成功! (主进程 PID: ${green}$PID${reset})"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}📌 隧道信息:"
    echo -e "  🔵 本地端口: ${lightpink}$PORT${reset}"
    echo -e "  🆔 隧道 ID: ${lightpink}$TUNNEL_ID${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${lightpink}📌 实时日志路径: ${green}$LOG_FILE${reset}"
    echo -e "${yellow}❗ 请等待 1-2 分钟让 Cloudflare 完成状态同步${reset}"
else
    error "隧道启动失败!"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${red}⚠️ 可能原因:"
    echo -e "1. 配置错误或证书缺失"
    echo -e "2. Cloudflared 文件未设置可执行权限"
    echo -e "3. 网络不通或端口占用${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${lightpink}🔍 查看日志：${green}tail -n 20 $LOG_FILE${reset}"
fi

footer
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
