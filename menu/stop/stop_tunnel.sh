#!/bin/bash 
clear

# 颜色定义
cyan='\033[1;36m'
yellow='\033[1;33m'
orange='\033[38;5;208m'
green='\033[1;32m'
red='\033[1;31m'
white='\033[1;37m'
reset='\033[0m'

# 显示顶部边框和标题
function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "                                ${orange}🔴 停止 Cloudflare 隧道${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

# 显示底部边框
function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 主逻辑
header

# 检查 cloudflared 是否在运行
PID=$(pgrep -f "cloudflared tunnel run")

if [ -z "$PID" ]; then
    echo -e "${yellow}⚠️ 没有正在运行的 Cloudflare 隧道${reset}"
    footer
    read -p "$(echo -e "${cyan}按回车键返回...${reset}")" dummy
    bash /root/VPN/menu/stop_service.sh
    exit 0
fi

# 检查进程状态
STATE=$(ps -o stat= -p "$PID" | tr -d ' ')
CFD_BIN=$(command -v cloudflared)
TUNNEL_NAME=$($CFD_BIN tunnel list 2>/dev/null | awk 'NR>1 {print $2}' | head -n 1)

echo -e "${white}🔄 正在停止隧道: ${green}$TUNNEL_NAME${reset} (PID: ${green}$PID${reset})"

if [[ "$STATE" == *Z* ]]; then
    echo -e "${yellow}⚠️ 检测到僵尸进程，尝试回收...${reset}"
    PPID=$(ps -o ppid= -p "$PID" | tr -d ' ')
    echo -e "${white}📌 父进程为: ${green}$PPID${reset}，执行: kill -9 $PPID"
    kill -9 "$PPID" 2>/dev/null
    sleep 2
else
    kill -TERM "$PID"
    sleep 2

    if ps -p "$PID" > /dev/null; then
        echo -e "${yellow}⚠️ 正常终止失败，尝试强制停止...${reset}"
        kill -9 "$PID" 2>/dev/null
        sleep 1
    fi
fi

# 最终确认
if ! ps -p "$PID" > /dev/null; then
    echo -e "${green}✅ 隧道已成功停止${reset}"
else
    echo -e "${red}❌ 停止失败，请手动 kill -9 $PID${reset}"
fi

footer
read -p "$(echo -e "${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/stop_service.sh
