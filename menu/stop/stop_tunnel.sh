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
CLOUDFLARED_DIR="/root/.cloudflared"
CERT_FILE="$CLOUDFLARED_DIR/cert.pem"
CONFIG_FILE="$CLOUDFLARED_DIR/config_info.txt"
CONFIG_YML="$CLOUDFLARED_DIR/config.yml"
CLOUD_FLARED="/root/VPN/cloudflared" 

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "                                ${orange}🔴 停止 Cloudflare 隧道${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

header

# 获取正在运行的 Cloudflared PID
PIDS=($(pgrep -f "$CLOUD_FLARED tunnel run"))

if [ ${#PIDS[@]} -eq 0 ]; then
    echo -e "${yellow}⚠️ 未找到运行中的Cloudflare隧道进程${reset}"
    footer
    read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
    bash /root/VPN/menu/stop_service.sh
    exit 0
fi

# 获取 tunnel 名称信息
TUNNEL_INFO=$("$CLOUD_FLARED" tunnel list 2>/dev/null | awk 'NR>1 {print "名称:"$2, "ID:"$1}')

# 遍历终止进程
for PID in "${PIDS[@]}"; do
    echo -e "${yellow}🔄 正在处理进程 PID: ${green}$PID${reset}"
    STATE=$(ps -o stat= -p "$PID" 2>/dev/null | tr -d ' ')
    
    if [ -z "$STATE" ]; then
        echo -e "${yellow}⚠️ 进程不存在，跳过${reset}"
        continue
    fi

    if [[ "$STATE" == *Z* ]]; then
        echo -e "${yellow}⚠️ 检测到僵尸进程${reset}"
        PARENT_PID=$(ps -o ppid= -p "$PID" | tr -d ' ')
        if [ "$PARENT_PID" != "1" ]; then
            echo -e "${yellow}📌 强制终止父进程 $PARENT_PID${reset}"
            kill -9 "$PARENT_PID" 2>/dev/null
            sleep 1
        fi
    else
        kill -TERM "$PID" 2>/dev/null
        sleep 2
        if ps -p "$PID" >/dev/null; then
            echo -e "${yellow}⚠️ 正常终止失败，尝试强制终止 PID: $PID${reset}"
            kill -9 "$PID" 2>/dev/null
            sleep 1
        fi
    fi

    if ! ps -p "$PID" >/dev/null; then
        echo -e "${green}✅ 成功终止 PID: $PID${reset}"
    else
        echo -e "${red}❌ 无法终止 PID: $PID，请手动处理${reset}"
    fi

    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
done

# 显示隧道信息（如有）
if [ -n "$TUNNEL_INFO" ]; then
    echo -e "${yellow}📌 当前活动隧道：\n${TUNNEL_INFO}" | sed "s/^/ ${green}▸${reset} /"
fi

footer
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/stop_service.sh
