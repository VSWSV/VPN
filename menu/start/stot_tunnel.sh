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

# 终止所有隧道进程
kill_tunnel() {
    pkill -f "cloudflared tunnel run" && sleep 1
    if pgrep -f "cloudflared tunnel run" >/dev/null; then
        pkill -9 -f "cloudflared tunnel run"
    fi
}

# 通过 systemctl 启动隧道
start_with_systemctl() {
    echo -e "${cyan}🔄 正在通过 systemctl 启动隧道服务...${reset}"
    if systemctl start cloudflared.service; then
        success "隧道服务已通过 systemctl 启动"
        return 0
    else
        error "无法通过 systemctl 启动隧道服务"
        return 1
    fi
}

# 主逻辑
clear
header

# 强制终止残留进程
kill_tunnel >/dev/null 2>&1

if ! verify_config; then
    echo -e "${red}配置文件校验失败，请检查并修复${reset}"
    footer
    exit 1
fi

TUNNEL_ID=$(get_tunnel_id)

# 精准检测隧道主进程
if systemctl is-active --quiet cloudflared; then
    echo -e "${yellow}⚠️ 隧道已通过 systemd 启动 (主进程已运行)${reset}"
    footer
    exit 0
fi

if pgrep -f "cloudflared tunnel run" >/dev/null; then
    PID=$(pgrep -f "cloudflared tunnel run")
    echo -e "${yellow}⚠️ 隧道已在运行中 (主进程 PID: ${green}$PID${yellow})${reset}"
    footer
    exit 0
fi

info "正在启动隧道: ${green}$TUNNEL_ID${reset}"

# 尝试使用 systemctl 启动隧道
if ! start_with_systemctl; then
    # 如果 systemctl 启动失败，则使用 nohup 启动
    nohup cloudflared tunnel run > "$LOG_FILE" 2>&1 &
    sleep 5

    if pgrep -f "cloudflared tunnel run" >/dev/null; then
        PID=$(pgrep -f "cloudflared tunnel run")
        success "隧道启动成功! (主进程 PID: ${green}$PID${reset})"
        echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
        echo -e "${lightpink}📌 实时日志路径: ${green}$LOG_FILE${reset}"
    else
        error "隧道启动失败!"
        echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
        echo -e "${red}⚠️ 可能原因:" 
        echo -e "1. 配置错误或证书缺失"
        echo -e "2. Cloudflared 文件未设置可执行权限"
        echo -e "3. 网络不通或端口占用"
        echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
        echo -e "${lightpink}🔍 查看日志：${green}tail -n 20 $LOG_FILE${reset}"
    fi
fi
footer
read -p "$(echo -e "${cyan}按任意键返回上级菜单...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
