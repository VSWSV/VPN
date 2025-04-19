#!/bin/bash

# 颜色定义
cyan='\033[1;36m'
yellow='\033[1;33m'
orange='\033[38;5;208m'
lightpink='\033[38;5;218m'
green='\033[1;32m'
red='\033[1;31m'
reset='\033[0m'

# 显示标题
show_header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗"
    printf "${orange}%*s🛑 停止 Cloudflare 隧道%*s\n" $(( (83 - 18) / 2 )) "" $(( (83 - 18 + 1) / 2 )) ""
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

show_footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

info() { echo -e "${yellow}🔹 $1${reset}"; }
success() { echo -e "${lightpink}✅ $1${reset}"; }
error() { echo -e "${red}❌ $1${reset}"; }

# 主逻辑
main() {
    clear
    show_header
    
    # 检查运行状态
    if ! pgrep -f "cloudflared tunnel run" >/dev/null; then
        echo -e "${yellow}⚠️ 没有正在运行的 Cloudflare 隧道${reset}"
        show_footer
        read -p "$(echo -e "${yellow}按回车键返回...${reset}")" dummy
        return
    fi
    
    # 获取隧道信息
    PID=$(pgrep -f "cloudflared tunnel run")
    TUNNEL_NAME=$($CFD_BIN tunnel list | awk 'NR>1 {print $2}')
    
    info "正在停止隧道: ${green}$TUNNEL_NAME${reset} (PID: ${green}$PID${reset})"
    
    # 停止隧道
    kill -TERM "$PID"
    sleep 2
    
    # 验证停止结果
    if pgrep -f "cloudflared tunnel run" >/dev/null; then
        error "停止隧道失败!"
        echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
        echo -e "${red}⚠️ 尝试强制停止: ${green}kill -9 $PID${reset}"
    else
        success "隧道已停止"
        echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
        echo -e "${lightpink}🗑️ 已清理进程: ${green}$PID${reset}"
    fi
    
    show_footer
    read -p "$(echo -e "${yellow}按回车键返回...${reset}")" dummy
}

main
