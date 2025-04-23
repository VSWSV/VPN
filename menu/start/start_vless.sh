#!/bin/bash
clear
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# 颜色定义
cyan="\033[1;36m"; green="\033[1;32m"; yellow="\033[1;33m"
red="\033[1;31m"; orange="\033[38;5;208m"; white="\033[1;37m"; lightpink="\033[38;5;213m"; reset="\033[0m"

# 固定路径
VLESS_DIR="/root/VPN/VLESS"
CONFIG_PATH="$VLESS_DIR/config/vless.json"
LOG_PATH="$VLESS_DIR/logs/vless.log"
PID_PATH="$VLESS_DIR/pids/vless.pid"
SUB_FILE="$VLESS_DIR/subscriptions/vless_sub.txt"
XRAY_BIN="/root/VPN/xray/xray"
XRAY_DIR="/root/VPN/xray"

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${orange}                              🌠 启动 VLESS 服务                                ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

function check_xray() {
    if [ ! -f "$XRAY_BIN" ]; then
        echo -e "${red}❌ Xray核心未找到: $XRAY_BIN${reset}"
        echo -e "${yellow}请检查以下文件是否存在：${reset}"
        ls -lh "$XRAY_DIR" || echo "无法列出xray目录"
        return 1
    fi
    
    if [ ! -x "$XRAY_BIN" ]; then
        echo -e "${yellow}⚠️ 尝试修复执行权限...${reset}"
        if ! chmod +x "$XRAY_BIN"; then
            echo -e "${red}❌ 无法添加执行权限${reset}"
            echo -e "${yellow}尝试手动修复：sudo chmod +x $XRAY_BIN${reset}"
            return 1
        fi
    fi
    
    if ! "$XRAY_BIN" version &>/dev/null; then
        echo -e "${red}❌ Xray二进制验证失败${reset}"
        echo -e "${yellow}可能原因：架构不匹配或文件损坏${reset}"
        return 1
    fi
    
    local required_files=("geoip.dat" "geosite.dat")
    for file in "${required_files[@]}"; do
        if [ ! -f "$XRAY_DIR/$file" ]; then
            echo -e "${red}❌ 缺少必要资源文件: $file${reset}"
            return 1
        fi
    done
    
    return 0
}

function get_ips() {
    local ipv4 ipv6
    ipv4=$(curl -s4m3 --connect-timeout 3 ifconfig.co 2>/dev/null || echo "未检测到")
    ipv6=$(curl -s6m3 --connect-timeout 3 ifconfig.co 2>/dev/null || echo "未检测到")
    echo "$ipv4" "$ipv6"
}

function verify_config() {
    [ -f "$CONFIG_PATH" ] || { echo -e "${red}❌ 配置文件不存在于: $CONFIG_PATH${reset}"; return 1; }
    
    if ! jq -e '.inbounds[0]' "$CONFIG_PATH" &>/dev/null; then
        echo -e "${red}❌ 配置文件格式错误${reset}"
        echo -e "${yellow}请检查配置文件: $CONFIG_PATH${reset}"
        return 1
    fi
    
    local required_fields=("port" "settings.clients[0].id")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".inbounds[0].${field}" "$CONFIG_PATH" &>/dev/null; then
            echo -e "${red}❌ 配置缺少必要字段: $field${reset}"
            return 1
        fi
    done
    
    return 0
}

function config_prompt() {
    while true; do
        echo -e "${yellow}是否要现在配置 VLESS？${reset}"
        echo -e "${green}[Y] 是${reset} ${red}[N] 否${reset}"
        read -p "请输入选择 (Y/N): " choice
        
        case "$choice" in
            [Yy]|[Yy][Ee][Ss])
                bash /root/VPN/menu/config/config_vless.sh
                return $?
                ;;
            [Nn]|[Nn][Oo])
                bash /root/VPN/menu/start_service.sh
                return $?
                ;;
            *)
                echo -e "${red}无效输入，请重新选择${reset}"
                ;;
        esac
    done
}

function generate_connection_links() {
    local ipv4=$1 ipv6=$2

    # 增强参数提取
    local PORT UUID SNI FLOW SECURITY NETWORK PUBLIC_KEY SHORT_ID PATH HOST SERVICE_NAME
    PORT=$(jq -r '.inbounds[0].port' "$CONFIG_PATH")
    UUID=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_PATH")
    SNI=$(jq -r '.inbounds[0].streamSettings.tlsSettings.serverName // .inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$CONFIG_PATH")
    FLOW=$(jq -r '.inbounds[0].settings.clients[0].flow // "xtls-rprx-vision"' "$CONFIG_PATH")
    SECURITY=$(jq -r '.inbounds[0].streamSettings.security // "none"' "$CONFIG_PATH")
    NETWORK=$(jq -r '.inbounds[0].streamSettings.network // "tcp"' "$CONFIG_PATH")
    PUBLIC_KEY=$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey // empty' "$CONFIG_PATH")
    SHORT_ID=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0] // empty' "$CONFIG_PATH")
    PATH=$(jq -r '.inbounds[0].streamSettings.wsSettings.path // empty' "$CONFIG_PATH")
    HOST=$(jq -r '.inbounds[0].streamSettings.wsSettings.headers.Host // empty' "$CONFIG_PATH")
    SERVICE_NAME=$(jq -r '.inbounds[0].streamSettings.grpcSettings.serviceName // empty' "$CONFIG_PATH")

    # 构建基础参数
    local common_params="type=$NETWORK&encryption=none"
    [ -n "$FLOW" ] && common_params+="&flow=$FLOW"

    # 安全参数
    case "$SECURITY" in
        "tls")
            common_params+="&security=tls&sni=$SNI&fp=chrome"
            [ "$NETWORK" == "h2" ] && common_params+="&alpn=h2"
            ;;
        "reality")
            common_params+="&security=reality&sni=$SNI&pbk=$PUBLIC_KEY&sid=$SHORT_ID&fp=chrome"
            ;;
    esac

    # 传输协议参数
    case "$NETWORK" in
        "ws")
            [ -n "$PATH" ] && common_params+="&path=${PATH//\//%2F}"
            [ -n "$HOST" ] && common_params+="&host=$HOST"
            ;;
        "grpc")
            [ -n "$SERVICE_NAME" ] && common_params+="&mode=gun&serviceName=${SERVICE_NAME//\//%2F}"
            ;;
        "h2")
            [ -n "$PATH" ] && common_params+="&path=${PATH//\//%2F}"
            [ -n "$SNI" ] && common_params+="&host=$SNI"
            ;;
    esac

    # 生成链接
    generate_link "域名" "$SNI" "$PORT" "$common_params"
    [ "$ipv4" != "未检测到" ] && generate_link "IPv4" "$ipv4" "$PORT" "$common_params"
    [ "$ipv6" != "未检测到" ] && generate_link "IPv6" "[$ipv6]" "$PORT" "$common_params"
}

function generate_link() {
    local type=$1 host=$2 port=$3 params=$4
    local remark="VES-$type"
    
    echo -e "${green}🌐 $type连接:${reset}"
    echo "vless://${UUID}@${host}:${port}?${params}#${remark}"
    echo ""
}

# 主流程
header

# 检查并创建必要目录
mkdir -p "$(dirname "$LOG_PATH")" "$(dirname "$PID_PATH")" "$(dirname "$SUB_FILE")"

# 检查Xray核心
if ! check_xray; then
    footer
    exit 1
fi

# 检查是否已在运行
if [ -f "$PID_PATH" ] && ps -p "$(cat "$PID_PATH")" >/dev/null 2>&1; then
    # 获取双栈IP
    read -r ipv4 ipv6 <<< "$(get_ips)"
    
    echo -e "${green}🟢 服务正在运行 (PID: $(cat "$PID_PATH"))${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${orange}                              🔗 可用连接方式                                ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    
    generate_connection_links "$ipv4" "$ipv6"
    
    # 网络信息
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}📶 网络信息:"
    echo -e "🔵 监听端口: ${lightpink}$(jq -r '.inbounds[0].port' "$CONFIG_PATH")${reset}"
    echo -e "${green}IPv4: ${lightpink}$ipv4${reset}"
    echo -e "${green}IPv6: ${lightpink}$ipv6${reset}"
    
    footer
    read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1 -r
    bash /root/VPN/menu/start_service.sh
    exit 0
fi

# 配置验证
if ! verify_config; then
    config_prompt
    exit $?
fi

# 提取配置参数
PORT=$(jq -r '.inbounds[0].port' "$CONFIG_PATH")
UUID=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_PATH")
SNI=$(jq -r '.inbounds[0].streamSettings.tlsSettings.serverName // .inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$CONFIG_PATH")
SECURITY=$(jq -r '.inbounds[0].streamSettings.security // "none"' "$CONFIG_PATH")

# 获取双栈IP
read -r ipv4 ipv6 <<< "$(get_ips)"

# 端口检查
if ss -tulnp | grep -q ":$PORT "; then
    echo -e "${red}❌ 端口 $PORT 已被占用${reset}"
    echo -e "${yellow}占用进程信息：${reset}"
    ss -tulnp | grep ":$PORT "
    footer
    read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1 -r
    bash /root/VPN/menu/start_service.sh
    exit 1
fi

# 启动服务
echo -e "${yellow}🔄 正在启动服务...${reset}"
echo -e "${cyan}程序路径: ${lightpink}$XRAY_BIN${reset}"
echo -e "${cyan}配置文件路径: ${lightpink}$CONFIG_PATH${reset}"

{
    echo "=== 启动时间: $(date '+%Y-%m-%d %H:%M:%S') ==="
    echo "Xray版本: $("$XRAY_BIN" version | head -1)"
    echo "启动命令: $XRAY_BIN run -config $CONFIG_PATH"
    echo "工作目录: $(pwd)"
    echo "环境变量:"
    export
    echo "----------------------------------------"
    
    # 设置资源文件路径
    export XRAY_LOCATION_ASSET="$XRAY_DIR"
    "$XRAY_BIN" run -config "$CONFIG_PATH"
} >> "$LOG_PATH" 2>&1 &

echo $! > "$PID_PATH"
sleep 2

# 状态检查
if ps -p "$(cat "$PID_PATH")" >/dev/null 2>&1; then
    # 生成订阅文件
    {
        echo "# VLESS 订阅链接 - 生成于 $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Xray版本: $("$XRAY_BIN" version | head -1)"
        echo ""
        generate_connection_links "$ipv4" "$ipv6" | while read -r line; do
            if [[ "$line" == vless://* ]]; then
                echo -n "$line" | base64 -w 0
                echo ""
            fi
        done
    } > "$SUB_FILE"
    
    echo -e "${green}✅ 启动成功! PID: $(cat "$PID_PATH")${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${orange}                              🔗 可用连接方式                                ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    
    generate_connection_links "$ipv4" "$ipv6"
    
    # 网络信息
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${green}📶 网络信息:"
    echo -e "🔵 监听端口: ${lightpink}$PORT${reset}"
    echo -e "${green}IPv4: ${lightpink}$ipv4${reset}"
    echo -e "${green}IPv6: ${lightpink}$ipv6${reset}"
    echo -e "${yellow}📝 订阅文件已生成: ${lightpink}$SUB_FILE${reset}"
else
    echo -e "${red}❌ 启动失败! 查看日志: ${lightpink}$LOG_PATH${reset}"
    echo -e "${yellow}可能原因:"
    echo -e "  1. 端口被占用"
    echo -e "  2. 证书配置错误"
    echo -e "  3. Xray核心未正确安装"
    echo -e "  4. 内存不足"
    echo -e "  5. 资源文件缺失"
    
    # 显示日志最后10行
    echo -e "\n${cyan}=== 日志最后10行 ===${reset}"
    tail -n 10 "$LOG_PATH" | sed 's/^/  /'
    
    # 清理无效PID文件
    [ -f "$PID_PATH" ] && rm -f "$PID_PATH"
fi

footer
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1 -r
bash /root/VPN/menu/start_service.sh
