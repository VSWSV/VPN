#!/bin/bash
clear

# 颜色定义 - 使用更专业的配色方案
title="\033[1;36m"      # 标题/边框 - 青色
success="\033[1;32m"    # 成功 - 亮绿色
warning="\033[1;33m"    # 警告 - 黄色
error="\033[1;31m"      # 错误 - 红色
info="\033[1;37m"       # 信息 - 白色
highlight="\033[1;35m"  # 高亮 - 紫色
reset="\033[0m"         # 重置颜色

# 路径配置
VLESS_DIR="/root/VPN/VLESS"
PID_FILE="$VLESS_DIR/pids/vless.pid"
LOG_FILE="$VLESS_DIR/logs/vless.log"
PROCESS_NAME="xray"  # Xray核心进程名

function header() {
    echo -e "${title}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${title}                              🔴 停止 VLESS 服务                                ${reset}"
    echo -e "${title}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${title}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 主流程
header

# 检查PID文件是否存在
if [ ! -f "$PID_FILE" ]; then
    echo -e "${warning}⚠️  未找到PID文件，尝试通过进程名停止...${reset}"
    
    # 通过进程名和配置文件路径查找
    VLESS_PID=$(pgrep -f "$PROCESS_NAME.*$VLESS_DIR/config/vless.json")
    
    if [ -z "$VLESS_PID" ]; then
        echo -e "${success}✅ 未找到运行中的VLESS进程${reset}"
        footer
        read -p "$(echo -e "${title}按任意键返回...${reset}")" -n 1
        bash /root/VPN/menu/stop_service.sh
        exit 0
    fi
else
    VLESS_PID=$(cat "$PID_FILE")
fi

# 停止进程
if [ -n "$VLESS_PID" ]; then
    echo -e "${info}🔄 正在停止PID为 ${highlight}$VLESS_PID${reset}${info} 的进程...${reset}"

    # 获取进程状态
    STATE=$(ps -o stat= -p "$VLESS_PID" | tr -d ' ')

    # 如果是僵尸进程
    if [[ "$STATE" == *Z* ]]; then
        echo -e "${warning}⚠️  检测到僵尸进程（Zombie）...${reset}"
        PPID=$(ps -o ppid= -p "$VLESS_PID" | tr -d ' ')
        echo -e "${info}📌 僵尸进程的父进程为：${highlight}$PPID${reset}${info}，尝试强制回收...${reset}"
        kill -9 "$PPID" 2>/dev/null
        sleep 2
    else
        # 正常终止
        kill -TERM "$VLESS_PID" 2>/dev/null
        sleep 3

        # 检查是否仍在运行
        if ps -p "$VLESS_PID" >/dev/null; then
            echo -e "${warning}⚠️  正常终止失败，尝试强制停止...${reset}"
            kill -9 "$VLESS_PID" 2>/dev/null
            sleep 1
        fi
    fi

    # 最终确认
    if ! ps -p "$VLESS_PID" >/dev/null; then
        echo -e "${success}✅ 成功停止VLESS服务${reset}"
        [ -f "$PID_FILE" ] && rm -f "$PID_FILE"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 服务已手动停止" >> "$LOG_FILE"
    else
        echo -e "${error}❌ 停止失败，请手动检查进程 ${highlight}$VLESS_PID${reset}"
        echo -e "${warning}尝试执行: kill -9 $VLESS_PID${reset}"
    fi
else
    echo -e "${success}✅ 未检测到运行中的VLESS服务${reset}"
fi

footer
read -p "$(echo -e "${title}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/stop_service.sh
