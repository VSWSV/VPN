#!/bin/bash

# 颜色定义
cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
lightpink="\033[38;5;213m"
reset="\033[0m"

CONFIG_PATH="/root/VPN/config/vless.json"
LOG_PATH="/root/VPN/logs/vless.log"
PID_PATH="/root/VPN/pids/vless.pid"
SUBSCRIPTION_DIR="/root/VPN/subscriptions"
SUBSCRIPTION_FILE="$SUBSCRIPTION_DIR/vless_sub.txt"

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}                              🚀 启动 VLESS 服务                                ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

clear
header

# 检查配置文件
if [ ! -f "$CONFIG_PATH" ]; then
    echo -e "${red}❌ 错误: 未找到 VLESS 配置文件${reset}"
    echo -e "${yellow}请先运行配置脚本创建配置文件: ${lightpink}bash /root/VPN/menu/config/config_vless.sh${reset}"
    footer
    exit 1
fi

# 检查是否已在运行
if [ -f "$PID_PATH" ]; then
    PID=$(cat "$PID_PATH")
    if ps -p "$PID" > /dev/null; then
        echo -e "${yellow}⚠️  VLESS 服务已在运行 (PID: $PID)${reset}"
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
echo -e "\n${yellow}🔄 正在启动 VLESS 服务...${reset}"
nohup /root/VPN/xray/xray run -config "$CONFIG_PATH" > "$LOG_PATH" 2>&1 &
VLESS_PID=$!
echo "$VLESS_PID" > "$PID_PATH"

sleep 2

# 验证是否启动成功
if ps -p "$VLESS_PID" > /dev/null; then
    echo -e "\n${green}✅ VLESS 服务启动成功! (PID: $VLESS_PID)${reset}"
    echo -e "${yellow}📝 日志文件: ${lightpink}$LOG_PATH${reset}"
    
    # 生成客户端配置
    CLIENT_CONFIG="/root/VPN/client_configs/vless_${SNI}.json"
    cat > "$CLIENT_CONFIG" <<EOF
{
  "v": "2",
  "ps": "VLESS_${SNI}",
  "add": "$IPV4",
  "port": "$PORT",
  "id": "$UUID",
  "aid": "0",
  "scy": "none",
  "net": "tcp",
  "type": "none",
  "host": "$SNI",
  "path": "",
  "tls": "tls",
  "sni": "$SNI",
  "alpn": "h3",
  "fp": "chrome"
}
EOF

    # 生成订阅链接
    BASE64_CONFIG=$(base64 -w 0 "$CLIENT_CONFIG")
    SUBSCRIPTION_LINK="vless://$(echo "$UUID@$IPV4:$PORT?type=tcp&security=tls&sni=$SNI&alpn=h3&fp=chrome#VLESS_$SNI" | base64 -w 0)"
    echo "$SUBSCRIPTION_LINK" > "$SUBSCRIPTION_FILE"
    
    echo -e "\n${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}                              📋 客户端配置信息                                  ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}✔️  客户端配置文件已生成: ${lightpink}$CLIENT_CONFIG${reset}"
    echo -e "${green}🔗 IPv4 连接地址: ${lightpink}$IPV4:$PORT${reset}"
    echo -e "${green}🔗 IPv6 连接地址: ${lightpink}$IPV6:$PORT${reset}"
    echo -e "${green}🔑 UUID: ${lightpink}$UUID${reset}"
    echo -e "${green}🌐 SNI 域名: ${lightpink}$SNI${reset}"
    echo -e "${green}📡 订阅链接: ${lightpink}$SUBSCRIPTION_LINK${reset}"
    echo -e "${yellow}📄 订阅文件路径: ${lightpink}$SUBSCRIPTION_FILE${reset}"
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
else
    echo -e "\n${red}❌ VLESS 服务启动失败!${reset}"
    echo -e "${yellow}请检查日志文件: ${lightpink}$LOG_PATH${reset}"
    footer
    exit 1
fi

footer

# 返回菜单
echo ""
read -p "$(echo -e "${cyan}按任意键返回主菜单...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
