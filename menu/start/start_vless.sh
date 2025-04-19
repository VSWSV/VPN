#!/bin/bash

# 配置区
VLESS_DIR="/root/VPN/VLESS"
CONFIG_PATH="$VLESS_DIR/config/vless.json"
LOG_PATH="$VLESS_DIR/logs/vless.log"
PID_PATH="$VLESS_DIR/pids/vless.pid"
CERTS_DIR="$VLESS_DIR/certs"

# 颜色定义
cyan="\033[1;36m"; green="\033[1;32m"; yellow="\033[1;33m"
red="\033[1;31m"; reset="\033[0m"

# 自动创建目录结构
mkdir -p "$VLESS_DIR"/{config,logs,pids,certs,client_configs,subscriptions}
chmod -R 700 "$VLESS_DIR"

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}                              🌠 启动 VLESS 服务                                 ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function generate_certs() {
    echo -e "${yellow}🔄 自动生成自签名证书...${reset}"
    openssl ecparam -genkey -name prime256v1 -out "$CERTS_DIR/private.key"
    openssl req -x509 -new -key "$CERTS_DIR/private.key" -out "$CERTS_DIR/cert.pem" \
        -days 365 -subj "/CN=$(jq -r '.inbounds[0].streamSettings.tlsSettings.serverName' "$CONFIG_PATH")"
    chmod 600 "$CERTS_DIR/"{cert.pem,private.key}
}

# 主流程
clear
header

# 证书检查
if [ ! -f "$CERTS_DIR/cert.pem" ] || [ ! -f "$CERTS_DIR/private.key" ]; then
    generate_certs
    tmp_config=$(mktemp)
    jq --arg cert "$CERTS_DIR/cert.pem" --arg key "$CERTS_DIR/private.key" \
       '.inbounds[0].streamSettings.tlsSettings += {"certificateFile":$cert,"keyFile":$key}' \
       "$CONFIG_PATH" > "$tmp_config" && mv "$tmp_config" "$CONFIG_PATH"
fi

# 启动服务
nohup /root/VPN/xray/xray run -config "$CONFIG_PATH" > "$LOG_PATH" 2>&1 &
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
