#!/bin/bash

# 颜色定义
cyan="\033[1;36m"; green="\033[1;32m"; yellow="\033[1;33m"
red="\033[1;31m"; orange="\033[38;5;208m"; white="\033[1;37m"; lightpink="\033[38;5;213m"; reset="\033[0m"

# 固定路径
VLESS_DIR="/root/VPN/VLESS"
CONFIG_PATH="$VLESS_DIR/config/vless.json"
LOG_PATH="$VLESS_DIR/logs/vless.log"
PID_PATH="$VLESS_DIR/pids/vless.pid"
SUB_FILE="$VLESS_DIR/subscriptions/vless_sub.txt"

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${orange}                              🌠 启动 VLESS 服务                                ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

function get_ips() {
    local ipv4 ipv6
    ipv4=$(curl -s4m3 --connect-timeout 3 ifconfig.co 2>/dev/null || echo "未检测到")
    ipv6=$(curl -s6m3 --connect-timeout 3 ifconfig.co 2>/dev/null || echo "未检测到")
    echo "$ipv4" "$ipv6"
}

function verify_config() {
    [ -f "$CONFIG_PATH" ] || { echo -e "${red}❌ 配置文件不存在"; return 1; }
    jq -e '.inbounds[0]' "$CONFIG_PATH" &>/dev/null || { echo -e "${red}❌ 配置文件格式错误"; return 1; }
    return 0
}

function config_prompt() {
    while true; do
        echo -e "${yellow}是否要现在配置 VLESS？${reset}"
        echo -e "${green}[Y] 是${reset} ${red}[N] 否${reset}"
        read -p "请输入选择 (Y/N): " choice
        
        case $choice in
            [Yy])
                bash /root/VPN/menu/config/config_vless.sh
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

function generate_connection_links() {
    local ipv4=$1
    local ipv6=$2
    
    # 1. 域名连接
    echo -e "${green}🌐 域名直连:${reset}"
    echo "vless://${UUID}@${SNI}:${PORT}?type=tcp&security=xtls&sni=${SNI}&flow=${FLOW}#VLESS-域名直连"
    echo ""
    
    # 2. IPv4连接
    if [[ "$ipv4" != "未检测到" ]]; then
        echo -e "${green}📡 IPv4直连:${reset}"
        echo "vless://${UUID}@${ipv4}:${PORT}?type=tcp&security=xtls&sni=${SNI}&flow=${FLOW}#VLESS-IPv4直连"
        echo ""
    else
        echo -e "${red}⚠️ IPv4地址未检测到${reset}"
    fi
    
    # 3. IPv6连接
    if [[ "$ipv6" != "未检测到" ]]; then
        echo -e "${green}📶 IPv6直连:${reset}"
        echo "vless://${UUID}@[${ipv6}]:${PORT}?type=tcp&security=xtls&sni=${SNI}&flow=${FLOW}#VLESS-IPv6直连"
        echo ""
    else
        echo -e "${red}⚠️ IPv6地址未检测到${reset}"
    fi
}

# 主流程
header

# 检查是否已在运行
if [ -f "$PID_PATH" ] && ps -p $(cat "$PID_PATH") >/dev/null; then
    # 提取配置参数
    PORT=$(jq -r '.inbounds[0].port' "$CONFIG_PATH")
    UUID=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_PATH")
    SNI=$(jq -r '.inbounds[0].streamSettings.tlsSettings.serverName // empty' "$CONFIG_PATH")
    FLOW=$(jq -r '.inbounds[0].settings.clients[0].flow // "xtls-rprx-vision"' "$CONFIG_PATH")
    
    # 获取双栈IP
    read -r ipv4 ipv6 <<< "$(get_ips)"
    
    echo -e "${green}🟢 服务正在运行 (PID: $(cat "$PID_PATH"))${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${orange}                              🔗 可用连接方式                                ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    
    generate_connection_links "$ipv4" "$ipv6"
    
    # 网络信息
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}📶 网络信息:"
    echo -e "  IPv4: ${lightpink}$ipv4${reset}"
    echo -e "  IPv6: ${lightpink}$ipv6${reset}"
    
    footer
    read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
    bash /root/VPN/menu/start_service.sh    
fi

# 配置验证
if ! verify_config; then
    config_prompt
    exit $?
fi

# 提取配置参数
PORT=$(jq -r '.inbounds[0].port' "$CONFIG_PATH")
UUID=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_PATH")
SNI=$(jq -r '.inbounds[0].streamSettings.tlsSettings.serverName // empty' "$CONFIG_PATH")
FLOW=$(jq -r '.inbounds[0].settings.clients[0].flow // "xtls-rprx-vision"' "$CONFIG_PATH")

# 获取双栈IP
read -r ipv4 ipv6 <<< "$(get_ips)"

# 端口检查
if ss -tulnp | grep -q ":$PORT "; then
    echo -e "${red}❌ 端口 $PORT 已被占用${reset}"
    footer
    read -p "$(echo -e "${white}按任意键返回...${reset}")" -n 1
    bash /root/VPN/menu/start_service.sh
    exit 1
fi

# 启动服务
echo -e "${yellow}🔄 正在启动服务...${reset}"
nohup /root/VPN/xray run -config "$CONFIG_PATH" > "$LOG_PATH" 2>&1 &
echo $! > "$PID_PATH"
sleep 1

# 状态检查
if ps -p $(cat "$PID_PATH") >/dev/null; then
    # 生成订阅文件
    {
        echo "# VLESS 订阅链接 - 生成于 $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        generate_connection_links "$ipv4" "$ipv6"
    } > "$SUB_FILE"
    
    echo -e "${green}✅ 启动成功! PID: $(cat "$PID_PATH")${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${orange}                              🔗 可用连接方式                                ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    
    generate_connection_links "$ipv4" "$ipv6"
    
    # 网络信息
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}📶 网络信息:"
    echo -e "  IPv4: ${lightpink}$ipv4${reset}"
    echo -e "  IPv6: ${lightpink}$ipv6${reset}"
else
    echo -e "${red}❌ 启动失败! 查看日志: ${lightpink}$LOG_PATH${reset}"
    echo -e "${yellow}可能原因:"
    echo -e "  1. 端口被占用"
    echo -e "  2. 证书配置错误"
    echo -e "  3. Xray核心未正确安装"
    echo -e "  4. 内存不足${reset}"
fi

footer
read -p "$(echo -e "${white}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
