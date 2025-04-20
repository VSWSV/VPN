#!/bin/bash
clear

# 颜色定义
red="\033[1;31m"; green="\033[1;32m"; yellow="\033[1;33m"
cyan="\033[1;36m"; orange="\033[38;5;208m"; reset="\033[0m"

# 路径配置
VLESS_DIR="/root/VPN/VLESS"
PID_FILE="$VLESS_DIR/pids/vless.pid"
LOG_FILE="$VLESS_DIR/logs/vless.log"
PROCESS_NAME="xray"  # Xray核心进程名

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "                              🔴 停止 VLESS 服务                                "
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
    
    # 通过进程名和配置文件路径查找（精准匹配）
    VLESS_PIDS=($(pgrep -f "$PROCESS_NAME run.*$VLESS_DIR/config/vless.json"))
    
    if [ ${#VLESS_PIDS[@]} -eq 0 ]; then
        echo -e "${green}✅ 未找到运行中的VLESS进程${reset}"
        footer
        read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
        bash /root/VPN/menu/stop_service.sh
        exit 0
    fi
else
    VLESS_PIDS=($(cat "$PID_FILE"))
fi

# 停止进程
if [ ${#VLESS_PIDS[@]} -gt 0 ]; then
    for PID in "${VLESS_PIDS[@]}"; do
        echo -e "${yellow}🔄 正在处理进程 PID: ${green}$PID${reset}"
        
        # 获取进程状态
        STATE=$(ps -o stat= -p "$PID" 2>/dev/null | tr -d ' ')
        
        if [ -z "$STATE" ]; then
            echo -e "${yellow}⚠️  进程 $PID 不存在${reset}"
            continue
        fi

        # 处理僵尸进程
        if [[ "$STATE" == *Z* ]]; then
            echo -e "${yellow}⚠️  检测到僵尸进程（PID: $PID）...${reset}"
            PPID=$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')
            if [ -n "$PPID" ]; then
                echo -e "${yellow}📌 僵尸进程的父进程为：$PPID，尝试强制回收...${reset}"
                kill -9 "$PPID" 2>/dev/null
                sleep 1
            fi
        else
            # 正常终止
            kill -TERM "$PID" 2>/dev/null
            sleep 2
            
            # 检查是否仍在运行
            if ps -p "$PID" >/dev/null; then
                echo -e "${yellow}⚠️  正常终止失败，尝试强制停止 PID: $PID...${reset}"
                kill -9 "$PID" 2>/dev/null
                sleep 1
            fi
        fi

        # 最终确认
        if ! ps -p "$PID" >/dev/null; then
            echo -e "${green}✅ 成功停止进程 PID: $PID${reset}"
            # 清理PID文件
            if [ -f "$PID_FILE" ]; then
                sed -i "/^$PID$/d" "$PID_FILE"
                if [ ! -s "$PID_FILE" ]; then
                    rm -f "$PID_FILE"
                fi
            fi
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 进程 $PID 已停止" >> "$LOG_FILE"
        else
            echo -e "${red}❌ 停止进程 PID: $PID 失败，请手动检查${reset}"
        fi
        echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    done
else
    echo -e "${green}✅ 未检测到运行中的VLESS服务${reset}"
fi

footer
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/stop_service.sh
