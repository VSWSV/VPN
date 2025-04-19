#!/bin/bash

# 颜色定义
cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
lightpink="\033[38;5;213m"
reset="\033[0m"

CONFIG_PATH="/root/VPN/config/hysteria.yaml"
LOG_PATH="/root/VPN/logs/hysteria.log"
PID_PATH="/root/VPN/pids/hysteria.pid"
SUBSCRIPTION_DIR="/root/VPN/subscriptions"
SUBSCRIPTION_FILE="$SUBSCRIPTION_DIR/hy2_sub.txt"

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}                              🚀 启动 Hysteria 2 服务                            ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

clear
header

# 检查配置文件
if [ ! -f "$CONFIG_PATH" ]; then
    echo -e "${red}❌ 错误: 未找到 Hysteria 2 配置文件${reset}"
    echo -e "${yellow}请先运行配置脚本创建配置文件: ${lightpink}bash /root/VPN/menu/config/config_hy2.sh${reset}"
    footer
    exit 1
fi

# 检查是否已在运行
if [ -f "$PID_PATH" ]; then
    PID=$(cat "$PID_PATH")
    if ps -p "$PID" > /dev/null; then
        echo -e "${yellow}⚠️  Hysteria 2 服务已在运行 (PID: $PID)${reset}"
        footer
        exit 0
    fi
fi

# 创建必要目录
mkdir -p /root/VPN/logs /root/VPN/pids /root/VPN/client_configs $SUBSCRIPTION_DIR

# 获取配置信息
PORT=$(grep "listen:" "$CONFIG_PATH" | awk '{print $2}' | tr -d ':')
UUID=$(grep "password:" "$CONFIG_PATH" | awk -F'"' '{print $2}')
SNI=$(grep "sni:" "$CONFIG_PATH" | awk '{print $2}')
IPV4=$(curl -s4 ifconfig.co || echo "未知")
IPV6=$(curl -s6 ifconfig.co || echo "未知")

echo -e "${green}✔️  配置文件: ${lightpink}$CONFIG_PATH${reset}"
echo -e "${green}✔️  监听端口: ${lightpink}$PORT${reset}"
echo -e "${green}✔️  UUID: ${lightpink}$UUID${reset}"
echo -e "${green}✔️  SNI 域名: ${lightpink}$SNI${reset}"
echo -e "${green}✔️  IPv4 地址: ${lightpink}$IPV4${reset}"
echo -e "${green}✔️  IPv6 地址: ${lightpink}$IPV6${reset}"

# 启动服务
echo -e "\n${yellow}🔄 正在启动 Hysteria 2 服务...${reset}"
nohup /root/VPN/hysteria --config "$CONFIG_PATH" server > "$LOG_PATH" 2>&1 &
HY2_PID=$!
echo "$HY2_PID" > "$PID_PATH"

sleep 2

# 验证是否启动成功
if ps -p "$HY2_PID" > /dev/null; then
    echo -e "\n${green}✅ Hysteria 2 服务启动成功! (PID: $HY2_PID)${reset}"
    echo -e "${yellow}📝 日志文件: ${lightpink}$LOG_PATH${reset}"
    
    # 生成客户端配置
    CLIENT_CONFIG="/root/VPN/client_configs/hy2_${SNI}.json"
    cat > "$CLIENT_CONFIG" <<EOF
{
  "server": "$IPV4:$PORT",
  "server_name": "$SNI",
  "auth_str": "$UUID",
  "alpn": "h3",
  "protocol": "udp",
  "up_mbps": 100,
  "down_mbps": 100,
  "socks5": {
    "listen": "127.0.0.1:1080"
  },
  "http": {
    "listen": "127.0.0.1:8080"
  }
}
EOF

    # 生成订阅链接
    BASE64_CONFIG=$(base64 -w 0 "$CLIENT_CONFIG")
    SUBSCRIPTION_LINK="hy2://$(echo "$BASE64_CONFIG" | tr -d '\n')"
    echo "$SUBSCRIPTION_LINK" > "$SUBSCRIPTION_FILE"
    
    echo -e "\n${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}                              📋 客户端配置信息                                  ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}✔️  客户端配置文件已生成: ${lightpink}$CLIENT_CONFIG${reset}"
    echo -e "${green}🔗 IPv4 连接地址: ${lightpink}$IPV4:$PORT${reset}"
    echo -e "${green}🔗 IPv6 连接地址: ${lightpink}$IPV6:$PORT${reset}"
    echo -e "${green}🔑 认证密码: ${lightpink}$UUID${reset}"
    echo -e "${green}🌐 SNI 域名: ${lightpink}$SNI${reset}"
    echo -e "${green}📡 订阅链接: ${lightpink}$SUBSCRIPTION_LINK${reset}"
    echo -e "${yellow}📄 订阅文件路径: ${lightpink}$SUBSCRIPTION_FILE${reset}"
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
else
    echo -e "\n${red}❌ Hysteria 2 服务启动失败!${reset}"
    echo -e "${yellow}请检查日志文件: ${lightpink}$LOG_PATH${reset}"
    footer
    exit 1
fi

footer

# 返回菜单
echo ""
read -p "$(echo -e "${cyan}按任意键返回主菜单...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
