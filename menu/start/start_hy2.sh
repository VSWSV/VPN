#!/bin/bash

# 配置区
HY2_DIR="/root/VPN/HY2"
CONFIG_PATH="$HY2_DIR/config/hysteria.yaml"
LOG_PATH="$HY2_DIR/logs/hysteria.log"
PID_PATH="$HY2_DIR/pids/hysteria.pid"
CERTS_DIR="$HY2_DIR/certs"
DEFAULT_SNI="hy2.example.com"  # 默认域名，如果配置文件不存在时使用

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

function generate_config() {
    echo -e "${yellow}🔄 自动生成配置文件...${reset}"
    cat > "$CONFIG_PATH" <<EOF
listen: :443
protocol: hysteria2
auth:
  type: password
  password: "$(cat /proc/sys/kernel/random/uuid)"
tls:
  cert: $CERTS_DIR/cert.pem
  key: $CERTS_DIR/private.key
  sni: $DEFAULT_SNI
  alpn:
    - h3
EOF
}

function generate_certs() {
    local sni=${1:-$DEFAULT_SNI}
    echo -e "${yellow}🔄 自动生成自签名证书 (SNI: $sni)...${reset}"
    openssl ecparam -genkey -name prime256v1 -out "$CERTS_DIR/private.key"
    openssl req -x509 -new -key "$CERTS_DIR/private.key" -out "$CERTS_DIR/cert.pem" \
        -days 365 -subj "/CN=$sni"
    chmod 600 "$CERTS_DIR/"{cert.pem,private.key}
}

# 主流程
clear
header

# 配置文件检查
if [ ! -f "$CONFIG_PATH" ]; then
    generate_config
    generate_certs "$DEFAULT_SNI"
    echo -e "${yellow}⚠️ 已生成默认配置，请编辑 $CONFIG_PATH 修改参数${reset}"
fi

# 证书检查（从配置文件中读取SNI）
SNI=$(grep "sni:" "$CONFIG_PATH" 2>/dev/null | awk '{print $2}' || echo "$DEFAULT_SNI")
if [ ! -f "$CERTS_DIR/cert.pem" ] || [ ! -f "$CERTS_DIR/private.key" ]; then
    generate_certs "$SNI"
    # 更新配置文件中的证书路径
    sed -i "/tls:/,/^[^ ]/ {/cert:\|key:/d}" "$CONFIG_PATH"
    sed -i "/tls:/a \  cert: $CERTS_DIR/cert.pem\n  key: $CERTS_DIR/private.key" "$CONFIG_PATH"
fi

# 启动服务
echo -e "${yellow}🔄 正在启动服务...${reset}"
nohup /root/VPN/hysteria --config "$CONFIG_PATH" server > "$LOG_PATH" 2>&1 &
echo $! > "$PID_PATH"
sleep 1

# 状态检查
if ps -p $(cat "$PID_PATH" 2>/dev/null) >/dev/null 2>&1; then
    echo -e "${green}✅ 启动成功! PID: $(cat "$PID_PATH")${reset}"
    echo -e "${green}🔗 配置目录: $HY2_DIR${reset}"
else
    echo -e "${red}❌ 启动失败! 可能原因:"
    echo -e "1. 端口冲突 (运行: ss -tulnp | grep 443)"
    echo -e "2. 二进制文件缺失 (检查: ls /root/VPN/hysteria)"
    echo -e "3. 查看详细日志: tail -n 20 $LOG_PATH${reset}"
fi

echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
