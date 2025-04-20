#!/bin/bash

# 颜色定义
cyan="\033[1;36m"; green="\033[1;32m"; yellow="\033[1;33m"
red="\033[1;31m"; orange="\033[38;5;208m"; white="\033[1;37m"; lightpink="\033[38;5;213m"; reset="\033[0m"

# 固定路径
VLESS_DIR="/root/VPN/VLESS"
CONFIG_PATH="$VLESS_DIR/config/vless.json"
LOG_PATH="$VLESS_DIR/logs/vless.log"
PID_PATH="$VLESS_DIR/pids/vless.pid"

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${orange}                              🌠 启动 VLESS 服务                                ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

function verify_config() {
    if [ ! -f "$CONFIG_PATH" ]; then
        echo -e "${red}❌ 配置文件不存在${reset}"
        return 1
    fi
    
    if ! jq -e '.inbounds[0]' "$CONFIG_PATH" &>/dev/null; then
        echo -e "${red}❌ 配置文件格式错误${reset}"
        return 1
    fi
    
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

# 主流程
header

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
function get_ips() {
    local ipv4 ipv6
    ipv4=$(curl -s4m3 --connect-timeout 3 ifconfig.co 2>/dev/null || echo "未检测到")
    ipv6=$(curl -s6m3 --connect-timeout 3 ifconfig.co 2>/dev/null || echo "未检测到")
    echo "$ipv4" "$ipv6"
}
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
    echo -e "${green}✅ 启动成功! PID: $(cat "$PID_PATH")${reset}"
    
    # 生成订阅（IPv4优先，失败用IPv6）
    SUB_FILE="$VLESS_DIR/subscriptions/vless_sub.txt"
    PUBLIC_IP=${ipv4:-$ipv6}
    [ "$PUBLIC_IP" = "未检测到" ] && PUBLIC_IP="请手动填写服务器IP"
    
    SUB_LINK="vless://${UUID}@${PUBLIC_IP}:${PORT}?type=tcp&security=xtls&sni=${SNI}&flow=${FLOW}#${SNI}-VLESS"
    echo "$SUB_LINK" > "$SUB_FILE"
    
    echo -e "${green}📡 订阅链接已生成: ${lightpink}$SUB_FILE${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    
    # 显示订阅链接（自动换行）
    function wrap_subscription() {
        local sub="$1"
        local len=${#sub}
        if [ $len -gt 65 ]; then
            echo -e "${cyan}${sub:0:65}${reset}"
            echo -e "${cyan}${sub:65}${reset}"
        else
            echo -e "${cyan}$sub${reset}"
        fi
    }
    wrap_subscription "$SUB_LINK"
    
    # 显示完整网络信息
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}📶 网络信息:"
    echo -e "  ${lightpink}IPv4: ${green}$ipv4${reset}"
    echo -e "  ${lightpink}IPv6: ${green}$ipv6${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}🔧 连接参数:"
    echo -e "  ${lightpink}传输协议: ${green}tcp${reset}"
    echo -e "  ${lightpink}安全协议: ${green}xtls${reset}"
    echo -e "  ${lightpink}流控方式: ${green}$FLOW${reset}"
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
