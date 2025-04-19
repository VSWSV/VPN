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
CLOUDFLARED_CERT_DIR="/root/.cloudflared"  # Cloudflare 证书路径

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}                              🚀 启动 VLESS 服务                                ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

function check_certificates() {
    if [ -f "$CLOUDFLARED_CERT_DIR/cert.pem" ] && [ -f "$CLOUDFLARED_CERT_DIR/private.key" ]; then
        echo -e "${green}✔️  检测到 Cloudflare 证书文件${reset}"
        return 0
    else
        echo -e "${red}❌ 错误: 未找到证书文件${reset}"
        echo -e "${yellow}请确保以下文件存在:"
        echo -e "  - ${lightpink}$CLOUDFLARED_CERT_DIR/cert.pem${reset}"
        echo -e "  - ${lightpink}$CLOUDFLARED_CERT_DIR/private.key${reset}"
        footer
        exit 1
    fi
}

clear
header

# 检查配置文件
if [ ! -f "$CONFIG_PATH" ]; then
    echo -e "${red}❌ 错误: 未找到 VLESS 配置文件${reset}"
    echo -e "${yellow}请先运行配置脚本: ${lightpink}bash /root/VPN/menu/config/config_vless.sh${reset}"
    footer
    exit 1
fi

# 检查证书
check_certificates

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
mkdir -p /root/VPN/{logs,pids,client_configs,subscriptions}

# 获取配置信息
PORT=$(jq -r '.inbounds[0].port' "$CONFIG_PATH")
UUID=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_PATH")
SNI=$(jq -r '.inbounds[0].streamSettings.tlsSettings.serverName' "$CONFIG_PATH")
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
  "alpn": "h2",
  "fp": "chrome"
}
EOF

    # 生成订阅链接
    SUBSCRIPTION_LINK="vless://${UUID}@${IPV4}:${PORT}?type=tcp&security=tls&sni=${SNI}&alpn=h2&fp=chrome#VLESS_${SNI}"
    BASE64_LINK=$(echo -n "$SUBSCRIPTION_LINK" | base64 -w 0)
    echo "$BASE64_LINK" > "/root/VPN/subscriptions/vless_sub.txt"
    
    echo -e "\n${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}                              📋 客户端配置信息                                  ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}✔️  客户端配置文件: ${lightpink}$CLIENT_CONFIG${reset}"
    echo -e "${green}🔗 IPv4 连接地址: ${lightpink}$IPV4:$PORT${reset}"
    echo -e "${green}🔗 IPv6 连接地址: ${lightpink}$IPV6:$PORT${reset}"
    echo -e "${green}🔑 UUID: ${lightpink}$UUID${reset}"
    echo -e "${green}🌐 SNI 域名: ${lightpink}$SNI${reset}"
    echo -e "${green}📡 订阅链接 (Base64): ${lightpink}$BASE64_LINK${reset}"
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
else
    echo -e "\n${red}❌ VLESS 服务启动失败!${reset}"
    echo -e "${yellow}请检查日志文件: ${lightpink}$LOG_PATH${reset}"
    echo -e "${yellow}常见问题:"
    echo -e "1. 证书路径错误 → 检查 ${lightpink}$CLOUDFLARED_CERT_DIR/cert.pem${reset}"
    echo -e "2. 端口冲突 → 运行 ${lightpink}ss -tulnp | grep $PORT${reset}"
    echo -e "3. Xray 权限不足 → 运行 ${lightpink}chmod +x /root/VPN/xray/xray${reset}"
    footer
    exit 1
fi

footer

# 返回菜单
echo ""
read -p "$(echo -e "${cyan}按任意键返回主菜单...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
