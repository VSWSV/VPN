#!/bin/bash 
clear
# 颜色定义 (支持256色)
cyan='\033[1;36m'
yellow='\033[1;33m'
orange='\033[38;5;208m'
lightpink='\033[38;5;218m'
green='\033[1;32m'
red='\033[1;31m'
reset='\033[0m'

# ========================
# 美观的界面设计
# ========================
function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}║                                                                             ║${reset}"
    echo -e "${cyan}║${orange}                            🔴 停止 Cloudflare 隧道                            ${cyan}║${reset}"
    echo -e "${cyan}║                                                                             ║${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# ========================
# 增强型日志记录
# ========================
LOG_FILE="/root/VPN/cloudflared/tunnel.log"
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ========================
# 主逻辑
# ========================
clear
header

# 获取所有隧道进程 (精准匹配)
PIDS=($(pgrep -f "cloudflared tunnel run"))

if [ ${#PIDS[@]} -eq 0 ]; then
    echo -e "${yellow}⚠️ 没有正在运行的 Cloudflare 隧道${reset}"
    log "未检测到运行中的隧道进程"
    footer
    read -p "$(echo -e "${cyan}按回车键返回...${reset}")" dummy
    exit 0
fi

# ========================
# 获取隧道信息
# ========================
CFD_BIN=$(command -v cloudflared)
TUNNEL_INFO=$($CFD_BIN tunnel list 2>/dev/null | awk 'NR>1 {print "名称:"$2, "ID:"$1}')
log "检测到隧道信息: $TUNNEL_INFO"

# ========================
# 增强型进程停止逻辑
# ========================
success_count=0
failure_count=0

for PID in "${PIDS[@]}"; do
    echo -e "${cyan}║${reset}"
    echo -e "${yellow}🔄 正在处理进程 PID: ${green}$PID${reset}"
    log "开始处理进程 PID: $PID"
    
    # 检查进程是否存在
    if ! ps -p "$PID" >/dev/null; then
        echo -e "${yellow}⚠️ 进程不存在，跳过处理${reset}"
        log "跳过无效PID: $PID"
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
            log "终止僵尸进程父进程: $PPID"
        else
            echo -e "${red}❌ 拒绝终止系统关键进程${reset}"
            log "拒绝终止系统进程 PPID: $PPID"
        fi
    else
        # 优雅终止
        kill -TERM "$PID" 2>/dev/null
        sleep 2
        
        # 强制终止
        if ps -p "$PID" >/dev/null; then
            echo -e "${yellow}⚠️ 强制终止进程${reset}"
            kill -9 "$PID" 2>/dev/null
            sleep 1
        fi
    fi

    # 确认结果
    if ! ps -p "$PID" >/dev/null; then
        echo -e "${green}✅ 终止成功${reset}"
        ((success_count++))
        log "成功终止进程 PID: $PID"
    else
        echo -e "${red}❌ 终止失败${reset}"
        ((failure_count++))
        log "终止失败 PID: $PID"
    fi
done

# ========================
# 显示统计结果
# ========================
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e " 处理结果: ${green}成功 $success_count 个${reset} / ${red}失败 $failure_count 个${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e "${lightpink}📌 隧道信息:${reset}"
echo -e "${TUNNEL_INFO}" | while read line; do echo -e " ${green}▸${reset} $line"; done
log "隧道停止完成 成功: $success_count 失败: $failure_count"

footer
read -p "$(echo -e "${cyan}按回车键返回...${reset}")" dummy
exit 0
