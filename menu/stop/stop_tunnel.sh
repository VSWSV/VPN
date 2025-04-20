#!/bin/bash 
clear
# 颜色定义
cyan='\033[1;36m'
yellow='\033[1;33m'
orange='\033[38;5;208m'
lightpink='\033[38;5;218m'
green='\033[1;32m'
red='\033[1;31m'
reset='\033[0m'

# 显示顶部边框和标题
function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}                              ${orange}🔴 停止 Cloudflare 隧道${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 主逻辑
header

# PID 文件（未来扩展）
PID_FILE="/var/run/cloudflared.pid"
PID=""
PIDS=""

# 优先读取 PID 文件
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
else
    echo -e "${yellow}⚠️  未找到PID文件，尝试通过进程名停止...${reset}"
    PIDS=$(pgrep -f "cloudflared tunnel run")
fi

# 如果都找不到
if [ -z "$PID" ] && [ -z "$PIDS" ]; then
    echo -e "${green}✅ 未找到运行中的Cloudflare隧道${reset}"
    footer
    read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
    bash /root/VPN/menu/stop_service.sh
    exit 0
fi

# 获取隧道名称
CFD_BIN=$(command -v cloudflared)
TUNNEL_NAME=$($CFD_BIN tunnel list 2>/dev/null | awk 'NR>1 {print $2}' | head -n 1)

# 处理单个 PID（来自文件）
if [ -n "$PID" ]; then
    echo -e "${yellow}🔄 正在停止隧道: ${green}$TUNNEL_NAME${reset} (PID: ${green}$PID${reset})"
    STATE=$(ps -o stat= -p "$PID" | tr -d ' ')
    if [[ "$STATE" == *Z* ]]; then
        PPID=$(ps -o ppid= -p "$PID" | tr -d ' ')
        echo -e "${yellow}⚠️  检测到僵尸进程，父进程 $PPID，尝试 kill -9${reset}"
        kill -9 "$PPID" 2>/dev/null
        sleep 2
    else
        kill -TERM "$PID" 2>/dev/null
        sleep 2
        if ps -p "$PID" > /dev/null; then
            echo -e "${yellow}⚠️  正常终止失败，尝试 kill -9${reset}"
            kill -9 "$PID" 2>/dev/null
        fi
    fi

    if ! ps -p "$PID" > /dev/null; then
        echo -e "${green}✅ 成功停止 Cloudflare 隧道${reset}"
    else
        echo -e "${red}❌ 停止失败，请手动 kill -9 $PID${reset}"
    fi
fi

# 处理多个 PID（来自进程名）
if [ -n "$PIDS" ]; then
    for PID in $PIDS; do
        echo -e "${yellow}🔄 正在停止隧道: ${green}$TUNNEL_NAME${reset} (PID: ${green}$PID${reset})"
        STATE=$(ps -o stat= -p "$PID" | tr -d ' ')
        if [[ "$STATE" == *Z* ]]; then
            PPID=$(ps -o ppid= -p "$PID" | tr -d ' ')
            echo -e "${yellow}⚠️  检测到僵尸进程，父进程 $PPID，尝试 kill -9${reset}"
            kill -9 "$PPID" 2>/dev/null
        else
            kill -TERM "$PID" 2>/dev/null
            sleep 2
            if ps -p "$PID" > /dev/null; then
                echo -e "${yellow}⚠️  正常终止失败，尝试 kill -9${reset}"
                kill -9 "$PID" 2>/dev/null
            fi
        fi

        if ! ps -p "$PID" > /dev/null; then
            echo -e "${green}✅ 隧道 PID $PID 已成功停止${reset}"
        else
            echo -e "${red}❌ 停止失败，请手动 kill -9 $PID${reset}"
        fi
    done
fi

footer
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/stop_service.sh
