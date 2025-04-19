#!/bin/bash

# 颜色定义
cyan="\033[1;36m"; green="\033[1;32m"; yellow="\033[1;33m"
red="\033[1;31m"; reset="\033[0m"

# 固定路径
VLESS_DIR="/root/VPN/VLESS"
CONFIG_PATH="$VLESS_DIR/config/vless.json"
LOG_PATH="$VLESS_DIR/logs/vless.log"
PID_PATH="$VLESS_DIR/pids/vless.pid"

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}                              🌠 启动 VLESS 服务                                ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function verify_config() {
    [ -f "$CONFIG_PATH" ] || { echo -e "${red}❌ 配置文件不存在"; return 1; }
    jq -e '.inbounds[0]' "$CONFIG_PATH" &>/dev/null || { echo -e "${red}❌ 配置文件格式错误"; return 1; }
    return 0
}

# 主流程
header

# 配置验证
if ! verify_config; then
    echo -e "${yellow}请先运行配置脚本: ${lightpink}bash /root/VPN/menu/config/config_vless.sh${reset}"
    exit 1
fi

# 提取配置参数
PORT=$(jq -r '.inbounds[0].port' "$CONFIG_PATH")
UUID=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_PATH")
SNI=$(jq -r '.inbounds[0].streamSettings.tlsSettings.serverName // empty' "$CONFIG_PATH")

# 端口检查
if ss -tulnp | grep -q ":$PORT "; then
    echo -e "${red}❌ 端口 $PORT 已被占用${reset}"
    exit 1
fi

# 启动服务
echo -e "${yellow}🔄 正在启动服务...${reset}"
nohup /root/VPN/xray/xray run -config "$CONFIG_PATH" > "$LOG_PATH" 2>&1 &
echo $! > "$PID_PATH"
sleep 1

# 状态检查
if ps -p $(cat "$PID_PATH") >/dev/null; then
    echo -e "${green}✅ 启动成功! PID: $(cat "$PID_PATH")${reset}"
    
    # 生成订阅
    SUB_FILE="$VLESS_DIR/subscriptions/vless_sub.txt"
    cat > "$SUB_FILE" <<EOF
vless://$uuid@$(curl -s4 ifconfig.co):$port?type=tcp&security=xtls&sni=$sni&flow=xtls-rprx-vision#$SNI
EOF
    echo -e "${green}📡 订阅链接已生成: ${lightpink}$SUB_FILE${reset}"
else
    echo -e "${red}❌ 启动失败! 查看日志: ${lightpink}$LOG_PATH${reset}"
fi

footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}
footer

read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/start_service.sh
