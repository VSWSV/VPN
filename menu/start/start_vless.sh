#!/bin/bash

# 配置区
VLESS_DIR="/root/VPN/VLESS"
CONFIG_PATH="$VLESS_DIR/config/vless.json"
LOG_PATH="$VLESS_DIR/logs/vless.log"
PID_PATH="$VLESS_DIR/pids/vless.pid"
CERTS_DIR="$VLESS_DIR/certs"
DEFAULT_SNI="vless.example.com"  # 默认域名

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

function generate_config() {
    echo -e "${yellow}🔄 自动生成配置文件...${reset}"
    cat > "$CONFIG_PATH" <<EOF
{
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$(cat /proc/sys/kernel/random/uuid)",
            "flow": "xtls-rprx-vision"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$CERTS_DIR/cert.pem",
              "keyFile": "$CERTS_DIR/private.key"
            }
          ],
          "serverName": "$DEFAULT_SNI"
        }
      }
    }
  ]
}
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
SNI=$(jq -r '.inbounds[0].streamSettings.tlsSettings.serverName' "$CONFIG_PATH" 2>/dev/null || echo "$DEFAULT_SNI")
if [ ! -f "$CERTS_DIR/cert.pem" ] || [ ! -f "$CERTS_DIR/private.key" ]; then
    generate_certs "$SNI"
    # 更新配置文件中的证书路径
    tmp_config=$(mktemp)
    jq --arg cert "$CERTS_DIR/cert.pem" --arg key "$CERTS_DIR/private.key" \
       '.inbounds[0].streamSettings.tlsSettings.certificates[0] |= (.certificateFile = $cert | .keyFile = $key)' \
       "$CONFIG_PATH" > "$tmp_config" && mv "$tmp_config" "$CONFIG_PATH"
fi

# 启动服务
echo -e "${yellow}🔄 正在启动服务...${reset}"
nohup /root/VPN/xray/xray run -config "$CONFIG_PATH" > "$LOG_PATH" 2>&1 &
echo $! > "$PID_PATH"
sleep 1

# 状态检查
if ps -p $(cat "$PID_PATH" 2>/dev/null) >/dev/null 2>&1; then
    echo -e "${green}✅ 启动成功! PID: $(cat "$PID_PATH")${reset}"
    echo -e "${green}🔗 配置目录: $VLESS_DIR${reset}"
else
    echo -e "${red}❌ 启动失败! 可能原因:"
    echo -e "1. 端口冲突 (运行: ss -tulnp | grep 443)"
    echo -e "2. 二进制文件缺失 (检查: ls /root/VPN/xray/xray)"
    echo -e "3. 查看详细日志: tail -n 20 $LOG_PATH${reset}"
fi

echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
