#!/bin/bash

# 颜色定义
cyan="\033[1;36m"; green="\033[1;32m"; yellow="\033[1;33m"
red="\033[1;31m"; reset="\033[0m"

# 固定路径
HY2_DIR="/root/VPN/HY2"
CONFIG_PATH="$HY2_DIR/config/hysteria.yaml"
LOG_PATH="$HY2_DIR/logs/hysteria.log"
PID_PATH="$HY2_DIR/pids/hysteria.pid"

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}                              🚀 启动 Hysteria 2 服务                            ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function verify_config() {
    [ -f "$CONFIG_PATH" ] || { echo -e "${red}❌ 配置文件不存在"; return 1; }
    grep -q "password:" "$CONFIG_PATH" || { echo -e "${red}❌ 配置缺少password字段"; return 1; }
    
    if grep -q "tls:" "$CONFIG_PATH"; then
        grep -q "cert:" "$CONFIG_PATH" || { echo -e "${red}❌ 缺少cert路径"; return 1; }
        grep -q "key:" "$CONFIG_PATH" || { echo -e "${red}❌ 缺少key路径"; return 1; }
    fi
    return 0
}

# 主流程
header

# 配置验证
if ! verify_config; then
    echo -e "${yellow}请先运行配置脚本: ${lightpink}bash /root/VPN/menu/config/config_hy2.sh${reset}"
    exit 1
fi

# 提取配置参数
PORT=$(grep "listen:" "$CONFIG_PATH" | awk '{print $2}' | tr -d ':')
UUID=$(grep "password:" "$CONFIG_PATH" | awk -F'"' '{print $2}')
SNI=$(grep "sni:" "$CONFIG_PATH" | awk '{print $2}')

# 端口检查
if ss -tulnp | grep -q ":$PORT "; then
    echo -e "${red}❌ 端口 $PORT 已被占用${reset}"
    exit 1
fi

# 启动服务
echo -e "${yellow}🔄 正在启动服务...${reset}"
nohup /root/VPN/hysteria --config "$CONFIG_PATH" server > "$LOG_PATH" 2>&1 &
echo $! > "$PID_PATH"
sleep 1

# 状态检查
if ps -p $(cat "$PID_PATH") >/dev/null; then
    echo -e "${green}✅ 启动成功! PID: $(cat "$PID_PATH")${reset}"
    
    # 生成订阅
    SUB_FILE="$HY2_DIR/subscriptions/hy2_sub.txt"
    cat > "$SUB_FILE" <<EOF
hy2://$UUID@$(curl -s4 ifconfig.co):$PORT/?sni=$SNI&insecure=1#HY2_$SNI
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
