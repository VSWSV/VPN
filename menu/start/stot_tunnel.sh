#!/bin/bash

# 颜色定义
cyan='\033[1;36m'
yellow='\033[1;33m'
orange='\033[38;5;208m'
lightpink='\033[38;5;218m'
green='\033[1;32m'
red='\033[1;31m'
white='\033[1;37m'
reset='\033[0m'

# 路径配置
CLOUDFLARED_DIR="/root/.cloudflared"
CONFIG_FILE="$CLOUDFLARED_DIR/config_info.txt"
CFD_BIN="/root/VPN/cloudflared"
LOG_FILE="$CLOUDFLARED_DIR/tunnel.log"

# 标题
show_header() {
    clear
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗"
    printf "${orange}%*s🚀 启动 Cloudflare 隧道%*s\n" $(( (83 - 18) / 2 )) "" $(( (83 - 18 + 1) / 2 )) ""
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

show_footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

info() { echo -e "${yellow}🔹 $1${reset}"; }
success() { echo -e "${green}✅ $1${reset}"; }
error() { echo -e "${red}❌ $1${reset}"; }

# 验证配置
function verify_config() {
    [ -f "$CONFIG_FILE" ] || { echo -e "${red}❌ 配置文件不存在"; return 1; }
    grep -q "隧道名称：" "$CONFIG_FILE" || { echo -e "${red}❌ 配置缺少隧道名称字段"; return 1; }
    return 0
}

# 配置提示
function config_prompt() {
    while true; do
        echo -e "${yellow}是否要现在配置 Cloudflare 隧道？${reset}"
        echo -e "${green}[Y] 是${reset} ${red}[N] 否${reset}"
        read -p "请输入选择 (Y/N): " choice
        
        case $choice in
            [Yy])
                bash /root/VPN/menu/config/config_tunnel.sh
                return $?
                ;;
            [Nn])
                bash /root/VPN/menu/start_service.sh
                return $?
                ;;
            *)
                echo -e "${red}无效输入，请重新选择${reset}"
                ;;
        esac
    done
}

# 获取隧道名称
get_tunnel_name() {
    if verify_config; then
        grep "隧道名称：" "$CONFIG_FILE" | awk -F '：' '{print $2}'
    else
        config_prompt
        exit $?
    fi
}

# 主逻辑
main() {
    show_header

    TUNNEL_NAME=$(get_tunnel_name)

    # 检查是否已运行
    if pgrep -f "cloudflared tunnel run" >/dev/null; then
        PID=$(pgrep -f "cloudflared tunnel run")
        echo -e "${yellow}⚠️ 隧道已在运行中 (PID: ${green}$PID${yellow})${reset}"
        echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
        echo -e "${lightpink}📌 使用命令查看日志: ${green}tail -f $LOG_FILE${reset}"
        show_footer
        read -p "$(echo -e "${white}按回车键返回主菜单...${reset}")" -n 1
        bash /root/VPN/menu/start_service.sh
        return
    fi

    # 启动隧道
    info "正在启动隧道: ${green}$TUNNEL_NAME${reset}"
    nohup $CFD_BIN tunnel run "$TUNNEL_NAME" > "$LOG_FILE" 2>&1 &

    sleep 2

    # 检查启动结果
    if pgrep -f "cloudflared tunnel run" >/dev/null; then
        PID=$(pgrep -f "cloudflared tunnel run")
        success "隧道启动成功! (PID: ${green}$PID${reset})"
        echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
        echo -e "${lightpink}📌 实时日志路径: ${green}$LOG_FILE${reset}"
    else
        error "隧道启动失败!"
        echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
        echo -e "${red}⚠️ 可能原因:"
        echo -e "1. 证书未正确配置"
        echo -e "2. 配置文件损坏"
        echo -e "3. 端口冲突"
        echo -e "4. 网络连接问题${reset}"
        echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
        echo -e "${lightpink}🔍 查看错误详情: ${green}tail -n 20 $LOG_FILE${reset}"
    fi

    show_footer
    read -p "$(echo -e "${white}按回车键返回主菜单...${reset}")" -n 1
    bash /root/VPN/menu/start_service.sh
}

main
