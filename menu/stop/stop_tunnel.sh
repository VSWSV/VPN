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
LOG_DIR="/root/VPN/cloudflared"
[ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"

# 界面设计（严格保持原有样式）
function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "                                ${orange}🔴 停止 Cloudflare 隧道${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 主流程
header

# 进程检测
PIDS=($(pgrep -f "cloudflared tunnel run"))

if [ ${#PIDS[@]} -eq 0 ]; then
    echo -e "${yellow}⚠️  未找到PID文件，尝试通过进程名停止...${reset}"
    echo -e "${green}✅ 未找到运行中的Cloudflare隧道${reset}"
    footer
    read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
    bash /root/VPN/menu/stop_service.sh
    exit 0
fi

# 获取隧道信息
CFD_BIN=$(command -v cloudflared)
TUNNEL_INFO=$($CFD_BIN tunnel list 2>/dev/null | awk 'NR>1 {print "名称:"$2, "ID:"$1}')

# 进程停止逻辑（完整版）
for PID in "${PIDS[@]}"; do
    echo -e "${yellow}🔄 正在停止进程 PID: ${green}$PID${reset}"
    
    # 检查进程是否存在
    if ! ps -p "$PID" >/dev/null; then
        echo -e "${yellow}⚠️ 进程不存在，跳过处理${reset}"
        continue
    fi

    # 获取进程状态
    STATE=$(ps -o stat= -p "$PID" | tr -d ' ')
    
    # 处理僵尸进程
    if [[ "$STATE" == *Z* ]]; then
        echo -e "${yellow}⚠️ 检测到僵尸进程${reset}"
        PPID=$(ps -o ppid= -p "$PID" | tr -d ' ')
        
        if [ "$PPID" -ne 1 ] && [ -n "$PPID" ]; then
            echo -e "${yellow}📌 终止父进程 PPID: $PPID${reset}"
            kill -9 "$PPID" 2>/dev/null
            sleep 1
        else
            echo -e "${red}❌ 拒绝终止系统关键进程${reset}"
        fi
    fi

    # 终止进程
    kill -TERM "$PID" 2>/dev/null
    sleep 2
    if ps -p "$PID" >/dev/null; then
        echo -e "${yellow}⚠️ 强制终止进程${reset}"
        kill -9 "$PID" 2>/dev/null
        sleep 1
    fi

    # 确认结果
    if ! ps -p "$PID" >/dev/null; then
        echo -e "${green}✅ 终止成功${reset}"
    else
        echo -e "${red}❌ 终止失败，请手动检查${reset}"
    fi
    
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
done

# 显示隧道信息
if [ -n "$TUNNEL_INFO" ]; then
    echo -e "${yellow}📌 活动隧道信息:${reset}"
    echo "$TUNNEL_INFO" | while read line; do
        echo -e " ${green}▸${reset} $line"
    done
fi

footer
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/stop_service.sh
