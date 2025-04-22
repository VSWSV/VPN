#!/bin/bash
clear

# 颜色定义
cyan='\033[1;36m'
yellow='\033[1;33m'
orange='\033[38;5;208m'
green='\033[1;32m'
red='\033[1;31m'
reset='\033[0m'

# 路径配置
CLOUD_FLARED="/root/VPN/cloudflared"
PID_FILE="/root/VPN/pids/cloudflared.pid"

header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "                                ${orange}🔴 停止 Cloudflare 隧道${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}
footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

header

if [ -f "$PID_FILE" ]; then
    PIDS=($(cat "$PID_FILE"))
else
    echo -e "${yellow}⚠️ 未找到PID文件，尝试通过进程匹配...${reset}"
    PIDS=($(pgrep -f "$CLOUD_FLARED tunnel run"))
fi

if [ ${#PIDS[@]} -eq 0 ]; then
    echo -e "${green}✅ 未检测到运行中的Cloudflare隧道${reset}"
    footer
    read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
    bash /root/VPN/menu/stop_service.sh
    exit 0
fi

for PID in "${PIDS[@]}"; do
    echo -e "${yellow}🔄 正在处理进程 PID: ${green}$PID${reset}"
    STATE=$(ps -o stat= -p "$PID" 2>/dev/null | tr -d ' ')
    if [ -z "$STATE" ]; then
        echo -e "${yellow}⚠️ 进程不存在${reset}"; continue
    fi

    if [[ "$STATE" == *Z* ]]; then
        PARENT_PID=$(ps -o ppid= -p "$PID" | tr -d ' ')
        if [ "$PARENT_PID" != "1" ]; then
            echo -e "${yellow}📌 回收父进程 PID: $PARENT_PID${reset}"
            kill -9 "$PARENT_PID" 2>/dev/null
        fi
    else
        kill -TERM "$PID" 2>/dev/null; sleep 2
        ps -p "$PID" >/dev/null && kill -9 "$PID" 2>/dev/null
    fi

    if ! ps -p "$PID" >/dev/null; then
        echo -e "${green}✅ 已成功终止 PID: $PID${reset}"
        [ -f "$PID_FILE" ] && sed -i "/^$PID$/d" "$PID_FILE"
        [ -s "$PID_FILE" ] || rm -f "$PID_FILE"
    else
        echo -e "${red}❌ 无法终止 PID: $PID，请手动处理${reset}"
    fi

    PORT=$(ss -tulnp | grep "$PID" | grep -oP ':\K[0-9]+' | head -1)
    if [ -n "$PORT" ]; then
        echo -e "${red}❌ 端口 $PORT 仍被占用${reset}"
        PID_REMAIN=$(ss -tulnp | grep ":$PORT " | grep -oP 'pid=\K[0-9]+')
        echo -e "${yellow}👉 尝试强制释放 PID: $PID_REMAIN${reset}"
        kill -9 "$PID_REMAIN" 2>/dev/null
        sleep 1
        if ss -tulnp | grep -q ":$PORT "; then
            echo -e "${red}❌ 释放失败，请手动检查${reset}"
        else
            echo -e "${green}✅ 端口 $PORT 已强制释放${reset}"
        fi
    fi

    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
done

pkill -f cloudflared

footer
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/stop_service.sh
