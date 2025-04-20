#!/bin/bash 
clear

# 颜色定义
COLOR_BORDER="\033[1;36m"
COLOR_HEADER="\033[38;5;208m"
COLOR_SUCC="\033[1;32m"
COLOR_FAIL="\033[1;31m"
COLOR_WARN="\033[1;33m"
COLOR_INFO="\033[1;37m"
COLOR_VAR="\033[1;35m"
COLOR_RESET="\033[0m"

# 显示顶部边框和标题
function header() {
    echo -e "${COLOR_BORDER}╔═════════════════════════════════════════════════════════════════════════════════╗${COLOR_RESET}"
    echo -e "                                ${COLOR_HEADER}🔴 停止 Cloudflare 隧道${COLOR_RESET}"
    echo -e "${COLOR_BORDER}╠═════════════════════════════════════════════════════════════════════════════════╣${COLOR_RESET}"
}

# 显示底部边框
function footer() {
    echo -e "${COLOR_BORDER}╚═════════════════════════════════════════════════════════════════════════════════╝${COLOR_RESET}"
}

# 主逻辑
header

# 检查 cloudflared 是否在运行
PID=$(pgrep -f "cloudflared tunnel run")

if [ -z "$PID" ]; then
    echo -e "${COLOR_WARN}⚠️ 没有正在运行的 Cloudflare 隧道${COLOR_RESET}"
    footer
    read -p "$(echo -e "${COLOR_BORDER}按回车键返回...${COLOR_RESET}")" dummy
    bash /root/VPN/menu/stop_service.sh
    exit 0
fi

# 检查进程状态
STATE=$(ps -o stat= -p "$PID" | tr -d ' ')
CFD_BIN=$(command -v cloudflared)
TUNNEL_NAME=$($CFD_BIN tunnel list 2>/dev/null | awk 'NR>1 {print $2}' | head -n 1)

echo -e "${COLOR_INFO}🔄 正在停止隧道: ${COLOR_VAR}$TUNNEL_NAME${COLOR_RESET} (PID: ${COLOR_VAR}$PID${COLOR_RESET})"

if [[ "$STATE" == *Z* ]]; then
    echo -e "${COLOR_WARN}⚠️ 检测到僵尸进程，尝试回收...${COLOR_RESET}"
    PPID=$(ps -o ppid= -p "$PID" | tr -d ' ')
    echo -e "${COLOR_INFO}📌 父进程为: ${COLOR_VAR}$PPID${COLOR_RESET}，执行: kill -9 $PPID"
    kill -9 "$PPID" 2>/dev/null
    sleep 2
else
    kill -TERM "$PID"
    sleep 2

    if ps -p "$PID" > /dev/null; then
        echo -e "${COLOR_WARN}⚠️ 正常终止失败，尝试强制停止...${COLOR_RESET}"
        kill -9 "$PID" 2>/dev/null
        sleep 1
    fi
fi

# 最终确认
if ! ps -p "$PID" > /dev/null; then
    echo -e "${COLOR_SUCC}✅ 隧道已成功停止${COLOR_RESET}"
else
    echo -e "${COLOR_FAIL}❌ 停止失败，请手动 kill -9 $PID${COLOR_RESET}"
fi

footer
read -p "$(echo -e "${COLOR_BORDER}按回车键返回...${COLOR_RESET}")" dummy
bash /root/VPN/menu/stop_service.sh
