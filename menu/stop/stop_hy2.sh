#!/bin/bash
clear

red="\033[1;31m"; green="\033[1;32m"; yellow="\033[1;33m"
cyan="\033[1;36m"; orange="\033[38;5;208m"; reset="\033[0m"

HY2_DIR="/root/VPN/HY2"
CONFIG_PATH="$HY2_DIR/config/hysteria.yaml"
PID_FILE="$HY2_DIR/pids/hysteria.pid"
LOG_FILE="$HY2_DIR/logs/hysteria.log"
PROCESS_NAME="/root/VPN/hysteria"

TARGET_PORT=$(grep -E "^listen:" "$CONFIG_PATH" | sed -E 's/.*:([0-9]+)/\1/')

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${orange}                              🔴 停止 Hysteria 2 服务                          ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

header

if [ -z "$TARGET_PORT" ] || ! [[ "$TARGET_PORT" =~ ^[0-9]+$ ]]; then
    echo -e "${red}❌ 配置文件中未能解析有效监听端口，跳过端口释放检测${reset}"
    TARGET_PORT=""
fi

if [ ! -f "$PID_FILE" ]; then
    echo -e "${yellow}⚠️ 未找到PID文件，尝试通过进程匹配...${reset}"
    HY2_PIDS=($(pgrep -f "$PROCESS_NAME"))
    if [ ${#HY2_PIDS[@]} -eq 0 ]; then
        echo -e "${green}✅ 未找到运行中的Hysteria进程${reset}"
        footer
        read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
        bash /root/VPN/menu/stop_service.sh
        exit 0
    fi
else
    HY2_PIDS=($(cat "$PID_FILE"))
fi

if [ ${#HY2_PIDS[@]} -gt 0 ]; then
    for PID in "${HY2_PIDS[@]}"; do
        echo -e "${yellow}🔄 正在处理进程 PID: ${green}$PID${reset}"

        STATE=$(ps -o stat= -p "$PID" 2>/dev/null | tr -d ' ')
        if [ -z "$STATE" ]; then
            echo -e "${yellow}⚠️  进程 $PID 不存在${reset}"
            continue
        fi

        if [[ "$STATE" == *Z* ]]; then
            echo -e "${yellow}⚠️  检测到僵尸进程（PID: $PID）...${reset}"
            PARENT_PID=$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')
            if [ -n "$PARENT_PID" ]; then
                echo -e "${yellow}📌 尝试强制回收其父进程：$PARENT_PID${reset}"
                kill -9 "$PARENT_PID" 2>/dev/null
                sleep 1
            fi
        else
            kill -TERM "$PID" 2>/dev/null
            sleep 2
            if ps -p "$PID" >/dev/null; then
                echo -e "${yellow}⚠️  正常终止失败，尝试强制停止 PID: $PID...${reset}"
                kill -9 "$PID" 2>/dev/null
                sleep 1
            fi
        fi

        if ! ps -p "$PID" >/dev/null; then
            echo -e "${green}✅ 成功停止进程 PID: $PID${reset}"
            if [ -f "$PID_FILE" ]; then
                sed -i "/^$PID$/d" "$PID_FILE"
                [ ! -s "$PID_FILE" ] && rm -f "$PID_FILE"
            fi
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hysteria 进程 $PID 已停止" >> "$LOG_FILE"
        else
            echo -e "${red}❌ 停止进程 PID: $PID 失败，请手动检查${reset}"
        fi

        echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    done
else
    echo -e "${green}✅ 未检测到运行中的Hysteria服务${reset}"
fi

# 二次端口释放检测
if [ -n "$TARGET_PORT" ]; then
    PORT_STATUS=$(ss -tulnp | grep ":$TARGET_PORT ")
    if [[ -n "$PORT_STATUS" ]]; then
        PID_REMAIN=$(echo "$PORT_STATUS" | grep -oP 'pid=\K[0-9]+')
        echo -e "${yellow}👉 尝试强制释放残留进程 PID: $PID_REMAIN${reset}"
        kill -9 "$PID_REMAIN" 2>/dev/null
        sleep 1
        if ss -tulnp | grep -q ":$TARGET_PORT "; then
            echo -e "${red}❌ 释放失败，请手动检查${reset}"
        else
            echo -e "${green}✅ 已强制释放端口 $TARGET_PORT${reset}"
        fi
    else
        echo -e "${green}✅ 端口 $TARGET_PORT 已成功释放${reset}"
    fi
fi

pkill -f hysteria

footer
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/stop_service.sh
