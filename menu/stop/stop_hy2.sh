#!/bin/bash

# 颜色定义
red="\033[1;31m"; green="\033[1;32m"; yellow="\033[1;33m"
cyan="\033[1;36m"; reset="\033[0m"

# 路径配置
HY2_DIR="/root/VPN/HY2"
PID_FILE="$HY2_DIR/pids/hysteria.pid"
LOG_FILE="$HY2_DIR/logs/hysteria.log"

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}                              🛑 停止 Hysteria 2 服务                          ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 主流程
header

# 检查PID文件是否存在
if [ ! -f "$PID_FILE" ]; then
    echo -e "${yellow}⚠️  未找到PID文件，尝试通过进程名停止...${reset}"
    
    # 通过进程名查找
    HYSTERIA_PID=$(pgrep -f "hysteria server")
    if [ -z "$HYSTERIA_PID" ]; then
        echo -e "${green}✅ 未找到运行中的Hysteria进程${reset}"
        footer
        read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
        bash /root/VPN/menu/stop_service.sh
        exit 0
    fi
else
    HYSTERIA_PID=$(cat "$PID_FILE")
fi

# 停止进程
if [ -n "$HYSTERIA_PID" ]; then
    echo -e "${yellow}🔄 正在停止PID为 $HYSTERIA_PID 的进程...${reset}"

    # 获取进程状态
    STATE=$(ps -o stat= -p "$HYSTERIA_PID" | tr -d ' ')

    # 如果是僵尸进程
    if [[ "$STATE" == *Z* ]]; then
        echo -e "${yellow}⚠️  检测到僵尸进程（Zombie）...${reset}"
        PPID=$(ps -o ppid= -p "$HYSTERIA_PID" | tr -d ' ')
        echo -e "${yellow}📌 僵尸进程的父进程为：$PPID，尝试强制回收...${reset}"
        kill -9 "$PPID" 2>/dev/null
        sleep 2
    else
        # 正常终止
        kill -TERM "$HYSTERIA_PID" 2>/dev/null
        sleep 3

        # 检查是否仍在运行
        if ps -p "$HYSTERIA_PID" >/dev/null; then
            echo -e "${yellow}⚠️  正常终止失败，尝试强制停止...${reset}"
            kill -9 "$HYSTERIA_PID" 2>/dev/null
            sleep 1
        fi
    fi

    # 最终确认
    if ! ps -p "$HYSTERIA_PID" >/dev/null; then
        echo -e "${green}✅ 成功停止Hysteria服务${reset}"
        [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 服务已手动停止" >> "$LOG_FILE"
    else
        echo -e "${red}❌ 停止失败，请手动检查进程 ${HYSTERIA_PID}${reset}"
    fi
else
    echo -e "${green}✅ 未检测到运行中的Hysteria服务${reset}"
fi

footer
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/stop_service.sh
