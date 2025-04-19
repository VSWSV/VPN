#!/bin/bash

# 颜色定义
cyan="\033[1;36m"; green="\033[1;32m"; yellow="\033[1;33m"
red="\033[1;31m"; orange="\033[38;5;208m"; white="\033[1;37m"; reset="\033[0m"

# 固定路径
HY2_DIR="/root/VPN/HY2"
CONFIG_PATH="$HY2_DIR/config/hysteria.yaml"
LOG_PATH="$HY2_DIR/logs/hysteria.log"
PID_PATH="$HY2_DIR/pids/hysteria.pid"

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${orange}                              🚀 启动 Hysteria 2 服务                          ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function get_ips() {
    local ipv4 ipv6
    ipv4=$(curl -s4m3 --connect-timeout 3 ifconfig.co 2>/dev/null || echo "未检测到")
    ipv6=$(curl -s6m3 --connect-timeout 3 ifconfig.co 2>/dev/null || echo "未检测到")
    echo "$ipv4" "$ipv6"
}

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

function verify_config() {
    [ -f "$CONFIG_PATH" ] || { echo -e "${red}❌ 配置文件不存在"; return 1; }
    grep -q "password:" "$CONFIG_PATH" || { echo -e "${red}❌ 配置缺少password字段"; return 1; }
    return 0
}

# 主流程
header

# 配置验证
if ! verify_config; then
    echo -e "${yellow}请先运行配置脚本: bash /root/VPN/menu/config/config_hy2.sh${reset}"
    exit 1
fi

# 提取配置参数
PORT=$(grep "listen:" "$CONFIG_PATH" | awk '{print $2}' | tr -d ':')
UUID=$(grep "password:" "$CONFIG_PATH" | awk -F'"' '{print $2}')
SNI=$(grep "sni:" "$CONFIG_PATH" | awk '{print $2}')
ALPN=$(grep -A1 "alpn:" "$CONFIG_PATH" | tail -1 | tr -d ' -' || echo "h3")

# 获取双栈IP
read -r ipv4 ipv6 <<< "$(get_ips)"

# 端口检查
if ss -tulnp | grep -q ":$PORT "; then
    echo -e "${red}❌ 端口 $PORT 已被占用${reset}"
    exit 1
fi

# 启动服务
echo -e "${yellow}🔄 正在启动服务...${reset}"
nohup /root/VPN/hysteria/hysteria server --config "$CONFIG_PATH" > "$LOG_PATH" 2>&1 &
echo $! > "$PID_PATH"
sleep 1

# 状态检查
if ps -p $(cat "$PID_PATH") >/dev/null; then
    echo -e "${green}✅ 启动成功! PID: $(cat "$PID_PATH")${reset}"
    
    # 生成订阅（IPv4优先，失败用IPv6）
    SUB_FILE="$HY2_DIR/subscriptions/hy2_sub.txt"
    PUBLIC_IP=${ipv4:-$ipv6}
    [ "$PUBLIC_IP" = "未检测到" ] && PUBLIC_IP="请手动填写服务器IP"
    
    SUB_LINK="hysteria2://${UUID}@${PUBLIC_IP}:${PORT}?sni=${SNI}&alpn=${ALPN}&insecure=1#${SNI}-HY2"
    echo "$SUB_LINK" > "$SUB_FILE"
    
    echo -e "${green}📡 订阅链接已生成: ${lightpink}$SUB_FILE${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    wrap_subscription "$SUB_LINK"
    
    # 显示完整网络信息
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}📶 网络信息:"
    echo -e "  IPv4: ${lightpink}$ipv4${reset}"
    echo -e "  IPv6: ${lightpink}$ipv6${reset}"
else
    echo -e "${red}❌ 启动失败! 查看日志: ${lightpink}$LOG_PATH${reset}"
    echo -e "${yellow}可能原因:"
    echo "1. 端口被占用"
    echo "2. 证书配置错误"
    echo "3. 内核参数限制"
    echo -e "4. 内存不足${reset}"
fi

footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}
footer

read -p "$(echo -e "${white}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
