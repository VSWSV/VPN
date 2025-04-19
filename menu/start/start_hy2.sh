#!/bin/bash

# 配置区
HY2_DIR="/root/VPN/HY2"
CONFIG_PATH="$HY2_DIR/config/hysteria.yaml"
LOG_PATH="$HY2_DIR/logs/hysteria.log"
PID_PATH="$HY2_DIR/pids/hysteria.pid"
CERTS_DIR="$HY2_DIR/certs"

# 颜色定义
cyan="\033[1;36m"; green="\033[1;32m"; yellow="\033[1;33m"
red="\033[1;31m"; reset="\033[0m"

# 自动创建目录结构
mkdir -p "$HY2_DIR"/{config,logs,pids,certs,client_configs,subscriptions}
chmod -R 700 "$HY2_DIR"

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}                              🚀 启动 Hysteria 2 服务                            ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function generate_certs() {
    echo -e "${yellow}🔄 自动生成自签名证书...${reset}"
    openssl ecparam -genkey -name prime256v1 -out "$CERTS_DIR/private.key"
    openssl req -x509 -new -key "$CERTS_DIR/private.key" -out "$CERTS_DIR/cert.pem" \
        -days 365 -subj "/CN=$(grep "sni:" "$CONFIG_PATH" | awk '{print $2}')"
    chmod 600 "$CERTS_DIR/"{cert.pem,private.key}
}

# 主流程
clear
header

# 证书检查
if [ ! -f "$CERTS_DIR/cert.pem" ] || [ ! -f "$CERTS_DIR/private.key" ]; then
    generate_certs
    sed -i "/tls:/a \  cert: $CERTS_DIR/cert.pem\n  key: $CERTS_DIR/private.key" "$CONFIG_PATH"
fi

# 启动服务
nohup /root/VPN/hysteria --config "$CONFIG_PATH" server > "$LOG_PATH" 2>&1 &
echo $! > "$PID_PATH"

# 状态检查
if ps -p $(cat "$PID_PATH") >/dev/null; then
    echo -e "${green}✅ 启动成功! PID: $(cat "$PID_PATH")${reset}"
else
    echo -e "${red}❌ 启动失败! 查看日志: $LOG_PATH${reset}"
fi

echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
