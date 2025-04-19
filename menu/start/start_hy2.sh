#!/bin/bash

# 颜色定义
cyan="\033[1;36m"; green="\033[1;32m"; yellow="\033[1;33m"
red="\033[1;31m"; lightpink="\033[38;5;213m"; reset="\033[0m"

# 固定路径
HY2_DIR="/root/VPN/HY2"
HYSTERIA_BIN="/root/VPN/hysteria"  # 修正路径
CONFIG_PATH="$HY2_DIR/config/hysteria.yaml"
LOG_PATH="$HY2_DIR/logs/hysteria.log"
PID_PATH="$HY2_DIR/pids/hysteria.pid"

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}                              🚀 启动 Hysteria 2 服务                          ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function verify_binary() {
    [ -f "$HYSTERIA_BIN" ] || {
        echo -e "${red}❌ Hysteria 可执行文件不存在于: $HYSTERIA_BIN${reset}"
        echo -e "${yellow}请确保已正确安装Hysteria核心文件${reset}"
        exit 1
    }
    [ -x "$HYSTERIA_BIN" ] || {
        echo -e "${red}❌ 缺少执行权限: $HYSTERIA_BIN${reset}"
        echo -e "${yellow}尝试执行: chmod +x $HYSTERIA_BIN${reset}"
        exit 1
    }
}

function verify_config() {
    [ -f "$CONFIG_PATH" ] || { echo -e "${red}❌ 配置文件不存在"; return 1; }
    grep -q "password:" "$CONFIG_PATH" || { echo -e "${red}❌ 配置缺少password字段"; return 1; }
    
    if grep -q "tls:" "$CONFIG_PATH"; then
        grep -q "sni:" "$CONFIG_PATH" || { echo -e "${red}❌ 缺少SNI配置"; return 1; }
    fi
    return 0
}

function generate_subscription() {
    local uuid=$1
    local port=$2
    local sni=$3
    local alpn=$4
    
    # 获取公网IP（优先IPv4）
    local public_ip=$(curl -s4 ifconfig.co || curl -s6 ifconfig.co)
    
    # 生成标准Hysteria2订阅链接
    echo "hysteria2://${uuid}@${public_ip}:${port}?sni=${sni}&alpn=${alpn}&insecure=1#${sni}-HY2"
}

# 主流程
header

# 二进制文件验证
verify_binary

# 配置验证
if ! verify_config; then
    echo -e "${yellow}请先运行配置脚本: ${lightpink}bash /root/VPN/menu/config/config_hy2.sh${reset}"
    exit 1
fi

# 提取配置参数
PORT=$(grep "listen:" "$CONFIG_PATH" | awk '{print $2}' | tr -d ':')
UUID=$(grep "password:" "$CONFIG_PATH" | awk -F'"' '{print $2}')
SNI=$(grep "sni:" "$CONFIG_PATH" | awk '{print $2}')
ALPN=$(grep -A1 "alpn:" "$CONFIG_PATH" | tail -1 | tr -d ' -' || echo "h3")

# 端口检查
if ss -tulnp | grep -q ":$PORT "; then
    echo -e "${red}❌ 端口 $PORT 已被占用${reset}"
    exit 1
fi

# 启动服务
echo -e "${yellow}🔄 正在启动服务...${reset}"
nohup "$HYSTERIA_BIN" server --config "$CONFIG_PATH" > "$LOG_PATH" 2>&1 &
echo $! > "$PID_PATH"
sleep 2  # 增加等待时间

# 状态检查
if ps -p $(cat "$PID_PATH") >/dev/null; then
    echo -e "${green}✅ 启动成功! PID: $(cat "$PID_PATH")${reset}"
    
    # 生成订阅
    SUB_FILE="$HY2_DIR/subscriptions/hy2_sub.txt"
    generate_subscription "$UUID" "$PORT" "$SNI" "$ALPN" > "$SUB_FILE"
    
    echo -e "${green}📡 订阅链接已生成: ${lightpink}$SUB_FILE${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}$(cat $SUB_FILE)${reset}"
else
    echo -e "${red}❌ 启动失败! 查看日志: ${lightpink}$LOG_PATH${reset}"
    echo -e "${yellow}可能原因:"
    echo "1. 二进制文件执行失败"
    echo "2. 配置文件格式错误"
    echo "3. 系统资源不足"
    echo -e "4. 端口权限问题${reset}"
fi

footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}
footer

read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
