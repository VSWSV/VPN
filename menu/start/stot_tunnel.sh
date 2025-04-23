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
CLOUD_FLARED="/root/VPN/cloudflared"
PID_FILE="/root/VPN/pids/cloudflared.pid"
LOCK_FILE="/tmp/cloudflared.lock"

mkdir -p /root/VPN/pids

# 校验配置文件
verify_config() {
    [ -f "$CONFIG_FILE" ] || { echo -e "${red}❌ 缺少 config.yml 配置文件"; return 1; }

    CREDENTIALS_FILE=$(grep '^credentials-file:' "$CONFIG_FILE" | awk '{print $2}')
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        echo -e "${red}❌ 缺少认证凭证文件: $CREDENTIALS_FILE"; return 1;
    fi

    grep -q '^tunnel:' "$CONFIG_FILE" || { echo -e "${red}❌ 配置缺少必要字段"; return 1; }

    PORT=$(grep -A5 'ingress:' "$CONFIG_FILE" | grep -E 'http://[^:]+:([0-9]+)' | sed -E 's|.*:([0-9]+).*|\1|' | head -1)
    [ -z "$PORT" ] && PORT="未配置"

    return 0
}

# 获取隧道 ID
get_tunnel_id() {
    grep '^tunnel:' "$CONFIG_FILE" | awk '{print $2}'
}

# 输出边框
header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${orange}                              🚀 启动 Cloudflare 隧道                           ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}
footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

info() { echo -e "${yellow}🔹 $1${reset}"; }
success() { echo -e "${lightpink}✅ $1${reset}"; }
error() { echo -e "${red}❌ $1${reset}"; }

# 检查进程是否真正运行
is_tunnel_running() {
    # 检查PID文件是否存在且进程存活
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" >/dev/null 2>&1; then
            # 进一步验证是否是cloudflared进程
            if grep -q "$CLOUD_FLARED" /proc/$pid/cmdline 2>/dev/null; then
                return 0
            fi
        fi
    fi
    
    # 检查锁文件是否存在
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid=$(cat "$LOCK_FILE")
        if ps -p "$lock_pid" >/dev/null 2>&1; then
            return 0
        fi
    fi
    
    return 1
}

# 杀掉已有进程
kill_tunnel() {
    # 杀死通过PID文件记录的进程
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null && sleep 1
        if ps -p "$pid" >/dev/null 2>&1; then
            kill -9 "$pid" 2>/dev/null
        fi
    fi
    
    # 杀死所有可能的残留进程
    pkill -f "$CLOUD_FLARED tunnel run" && sleep 1
    pgrep -f "$CLOUD_FLARED tunnel run" >/dev/null && pkill -9 -f "$CLOUD_FLARED tunnel run"
    
    # 清理锁文件
    [ -f "$LOCK_FILE" ] && rm -f "$LOCK_FILE"
}

# 主逻辑开始
header

if ! verify_config; then
    echo -e "${yellow}⚠️ 检测配置失败，请检查配置文件${reset}"
    footer
    read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
    bash /root/VPN/menu/start_service.sh
    exit 1
fi

TUNNEL_ID=$(get_tunnel_id)
PORT=$(grep -A5 'ingress:' "$CONFIG_FILE" | grep -E 'http://[^:]+:([0-9]+)' | sed -E 's|.*:([0-9]+).*|\1|' | head -1)
[ -z "$PORT" ] && PORT="未配置"

# 检查是否已有进程（使用增强版检查）
if is_tunnel_running; then
    PID=$(cat "$PID_FILE" 2>/dev/null || pgrep -f "$CLOUD_FLARED tunnel run")
    echo -e "${yellow}🟢 服务正在运行 (主进程 PID: ${green}$PID${yellow})${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}📌 隧道信息:"
    echo -e "🔵 本地端口: ${lightpink}$PORT${reset}"
    echo -e "${green}🆔 隧道 ID: ${lightpink}$TUNNEL_ID${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${lightpink}📌 使用命令查看日志: ${green}tail -f $LOG_FILE${reset}"
    footer
    read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
    bash /root/VPN/menu/start_service.sh
    exit 0
fi

# 清理旧的进程和文件
kill_tunnel >/dev/null 2>&1

# 创建锁文件防止重复启动
echo $$ > "$LOCK_FILE"

# 启动服务
info "正在启动隧道: ${green}$TUNNEL_ID${reset}"
nohup "$CLOUD_FLARED" tunnel --config "$CONFIG_FILE" run "$TUNNEL_ID" > "$LOG_FILE" 2>&1 &
TUNNEL_PID=$!
echo "$TUNNEL_PID" > "$PID_FILE"

# 等待启动结果
sleep 5

if is_tunnel_running; then
    success "隧道启动成功! (主进程 PID: ${green}$TUNNEL_PID${reset})"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}📌 隧道信息:"
    echo -e "🔵 本地端口: ${lightpink}$PORT${reset}"
    echo -e "${green}🆔 隧道 ID: ${lightpink}$TUNNEL_ID${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${lightpink}📌 实时日志路径: ${green}$LOG_FILE${reset}"
    echo -e "${yellow}❗ 请等待 1-2 分钟让 Cloudflare 完成状态同步${reset}"
else
    error "隧道启动失败!"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

    # 智能诊断
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${red}❌ 配置文件缺失：$CONFIG_FILE${reset}"
    elif [ -z "$TUNNEL_ID" ]; then
        echo -e "${red}❌ 配置中缺少 tunnel ID${reset}"
    elif [ ! -f "$CREDENTIALS_FILE" ]; then
        echo -e "${red}❌ 认证凭证文件缺失：$CREDENTIALS_FILE${reset}"
    elif [ ! -x "$CLOUD_FLARED" ]; then
        echo -e "${red}❌ 执行文件无权限或丢失：$CLOUD_FLARED${reset}"
    elif ! curl -s --connect-timeout 3 https://cloudflare.com >/dev/null; then
        echo -e "${red}❌ 无法连接 Cloudflare，请检查本机网络${reset}"
    elif grep -i error "$LOG_FILE" | tail -n 1 | grep -q .; then
        LAST_ERROR=$(grep -i error "$LOG_FILE" | tail -n 1)
        echo -e "${red}❌ 日志错误：${yellow}$LAST_ERROR${reset}"
    else
        echo -e "${red}❌ 启动失败，原因未知，请检查日志${reset}"
    fi

    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${lightpink}🔍 查看日志：${green}tail -n 20 $LOG_FILE${reset}"
    
    # 清理失败的启动
    kill_tunnel >/dev/null 2>&1
fi

# 移除锁文件
[ -f "$LOCK_FILE" ] && rm -f "$LOCK_FILE"

footer
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
