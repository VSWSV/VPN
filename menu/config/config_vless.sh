#!/bin/bash
clear
# 颜色定义
cyan="\033[1;36m"; blue="\033[1;34m"; green="\033[1;32m"; yellow="\033[1;33m"
red="\033[1;31m"; orange="\033[38;5;208m"; lightpink="\033[38;5;213m"; white="\033[1;37m"; reset="\033[0m"

# 目录配置
VLESS_DIR="/root/VPN/VLESS"
CONFIG_PATH="$VLESS_DIR/config/vless.json"
CERTS_DIR="$VLESS_DIR/certs"

function header() {
    clear
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${orange}                              🌈 配置 VLESS 节点                                ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

function show_status() {
    echo -e "${green}✔ ${1}${reset}" | awk '{printf "%-60s %s\n", $0, ""}'
}

function show_error() {
    echo -e "${red}✖ ${1}${reset}" | awk '{printf "%-60s %s\n", $0, ""}'
}

function validate_input() {
    case $1 in
        uuid) [[ "$2" =~ ^[0-9a-fA-F-]{36}$ ]] ;;
        port) [[ "$2" =~ ^[0-9]+$ ]] && [ "$2" -ge 1 ] && [ "$2" -le 65535 ] ;;
        domain) [[ "$2" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] ;;
        security) [[ "$2" =~ ^(tls|xtls|none)$ ]] ;;
    esac
}

function generate_random_port() {
    while true; do
        local port=$((RANDOM%30000+10000))
        if ! ss -tuln | grep -q ":$port "; then
            echo $port
            break
        fi
    done
}

function generate_certs() {
    echo
    echo -e "${yellow}🛠️  正在为 $1 生成自签名证书...${reset}"
    mkdir -p "$CERTS_DIR"
    openssl ecparam -genkey -name prime256v1 -out "$CERTS_DIR/private.key" 2>/dev/null
    openssl req -x509 -new -key "$CERTS_DIR/private.key" -out "$CERTS_DIR/cert.pem" \
        -days 365 -subj "/CN=$1" 2>/dev/null
    chmod 600 "$CERTS_DIR/"{cert.pem,private.key}
    show_status "证书已生成到 ${lightpink}$CERTS_DIR${reset}"
}

# 检查Xray版本并设置flow参数
function setup_flow_config() {
    local xray_bin="/root/VPN/xray/xray"
    if [ ! -f "$xray_bin" ]; then
        echo -e "${red}❌ Xray二进制文件不存在: $xray_bin${reset}"
        exit 1
    fi

    local version_info=$("$xray_bin" version 2>/dev/null || echo "0.0.0")
    local version=$(echo "$version_info" | awk '/Xray/{print $2}')

    if [[ "$version" == "0.0.0" ]]; then
        echo -e "${yellow}⚠️ 无法获取Xray版本，将使用兼容模式${reset}"
        echo '"flow": ""'
    elif [[ "$version" < "1.8.0" ]]; then
        echo -e "${yellow}⚠️ 检测到旧版Xray ($version)，将禁用flow控制${reset}"
        echo '"flow": ""'
    else
        echo -e "${green}✅ 检测到新版Xray ($version)，已启用xtls-rprx-vision${reset}"
        echo '"flow": "xtls-rprx-vision"'
    fi
}

# 初始化目录
mkdir -p "$VLESS_DIR"/{config,certs,logs,pids,client_configs,subscriptions}
chmod 700 "$VLESS_DIR" "$VLESS_DIR"/{config,certs,logs,pids}

# 主流程
header

# 现有配置检测
if [ -f "$CONFIG_PATH" ]; then
    current_uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_PATH" 2>/dev/null || echo "获取失败")
    current_port=$(jq -r '.inbounds[0].port' "$CONFIG_PATH" 2>/dev/null || echo "获取失败")
    current_sni=$(jq -r '.inbounds[0].streamSettings.tlsSettings.serverName // empty' "$CONFIG_PATH" 2>/dev/null || echo "未设置")
    current_security=$(jq -r '.inbounds[0].streamSettings.security // empty' "$CONFIG_PATH" 2>/dev/null || echo "none")
    current_ipv4=$(curl -s4 ifconfig.co || echo "获取失败")
    current_ipv6=$(curl -s6 ifconfig.co || echo "获取失败")

    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${orange}                              📝 当前配置预览                                  ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e " ${lightpink}UUID：     ${reset}${green}$current_uuid${reset}"
    echo -e " ${lightpink}端口：     ${reset}${green}$current_port${reset}"
    echo -e " ${lightpink}域名：     ${reset}${green}$current_sni${reset}"
    echo -e " ${lightpink}安全协议： ${reset}${green}$current_security${reset}"
    echo -e " ${lightpink}IPv4：     ${reset}${green}$current_ipv4${reset}"
    echo -e " ${lightpink}IPv6：     ${reset}${green}$current_ipv6${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

    while true; do
        read -p "$(echo -e "${yellow}是否覆盖当前配置？(y/N): ${reset}")" -n 1 overwrite
        echo
        case "$overwrite" in
            [Yy]) break ;;
            [Nn])
                clear
                bash /root/VPN/menu/config_node.sh
                exit ;;
            *)
                echo -e "${red}❌ 无效输入！${reset}"
                sleep 0.5
                while read -r -t 0; do read -r; done
                ;;
        esac
    done
fi

# 端口配置
while true; do
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    read -p "$(echo -e " ${lightpink}⇨ 请输入监听端口 [回车自动生成]: ${reset}")" port
    if [ -z "$port" ]; then
        port=$(generate_random_port)
        show_status "已自动生成可用端口: ${lightpink}$port${reset}"
        break
    elif validate_input "port" "$port"; then
        if ss -tuln | grep -q ":$port "; then
            show_error "端口 ${port} 已被占用"
        else
            show_status "端口设置为: ${lightpink}$port${reset}"
            break
        fi
    else
        show_error "无效端口 (1-65535)"
    fi
done

# UUID生成
uuid=$(cat /proc/sys/kernel/random/uuid)
show_status "自动生成 UUID: ${lightpink}$uuid${reset}"

# 域名配置
while true; do
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    read -p "$(echo -e " ${lightpink}⇨ 请输入SNI域名 (如: vpn.example.com): ${reset}")" sni
    if validate_input "domain" "$sni"; then
        show_status "域名设置为: ${lightpink}$sni${reset}"
        break
    else
        show_error "无效域名格式 (示例: example.com)"
    fi
done

# 安全协议配置
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e " ${lightpink}⇨ 请选择传输安全协议:${reset}"
echo -e "  ${green}① TLS (推荐)${reset}"
echo -e "  ${green}② XTLS (高性能)${reset}"
echo -e "  ${yellow}③ none (不加密)${reset}"
read -p "$(echo -e " ${blue}请选择：${reset}")" security_choice
case $security_choice in
    1) security="tls" ;;
    2) security="xtls" ;;
    3) security="none"; show_error "警告: 禁用加密将导致连接不安全!" ;;
    *) security="tls"; show_error "无效选择，默认使用TLS" ;;
esac

# TLS配置
if [[ "$security" != "none" ]]; then
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e " ${lightpink}⇨ 请选择证书配置:${reset}"
    echo -e "  ${green}① 使用自签名证书 (推荐测试用)${reset}"
    echo -e "  ${green}② 使用现有证书${reset}"
    read -p "$(echo -e " ${blue}请选择：${reset}")" tls_choice
    case $tls_choice in
        1)
            generate_certs "$sni"
            tls_config='"security": "'$security'",
    "tlsSettings": {
      "serverName": "'$sni'",
      "certificates": [
        {
          "certificateFile": "'$CERTS_DIR/cert.pem'",
          "keyFile": "'$CERTS_DIR/private.key'"
        }
      ]
    }'
            ;;
        2)
            while true; do
                read -p "$(echo -e " ${lightpink}⇨ 请输入证书路径: ${reset}")" cert_path
                read -p "$(echo -e " ${lightpink}⇨ 请输入私钥路径: ${reset}")" key_path
                if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
                    tls_config='"security": "'$security'",
    "tlsSettings": {
      "serverName": "'$sni'",
      "certificates": [
        {
          "certificateFile": "'$cert_path'",
          "keyFile": "'$key_path'"
        }
      ]
    }'
                    break
                else
                    show_error "证书文件不存在，请重新输入"
                fi
            done
            ;;
        *)
            show_error "无效选择，默认使用自签名证书"
            generate_certs "$sni"
            tls_config='"security": "'$security'",
    "tlsSettings": {
      "serverName": "'$sni'",
      "certificates": [
        {
          "certificateFile": "'$CERTS_DIR/cert.pem'",
          "keyFile": "'$CERTS_DIR/private.key'"
        }
      ]
    }'
            ;;
    esac
else
    tls_config='"security": "none"'
fi

# 设置flow参数
flow_config=$(setup_flow_config)

# 生成配置文件
cat > "$CONFIG_PATH" <<EOF
{
  "inbounds": [
    {
      "port": $port,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            $flow_config
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        $tls_config
      }
    }
  ]
}
EOF

chmod 600 "$CONFIG_PATH"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
show_status "配置文件已保存到: ${lightpink}$CONFIG_PATH${reset}"

# 显示连接信息
ipv4=$(curl -s4 ifconfig.co || echo "获取失败")
ipv6=$(curl -s6 ifconfig.co || echo "获取失败")

echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e "${orange}                              🔗 客户端连接信息                                  ${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e " ${lightpink}服务器地址: ${reset}${green}$sni${reset}"
echo -e " ${lightpink}连接端口:   ${reset}${green}$port${reset}"
echo -e " ${lightpink}用户ID：    ${reset}${green}$uuid${reset}"
echo -e " ${lightpink}传输协议:   ${reset}${green}tcp${reset}"
echo -e " ${lightpink}安全协议:   ${reset}${green}$security${reset}"
echo -e " ${lightpink}公网IPv4:   ${reset}${green}$ipv4${reset}"
echo -e " ${lightpink}公网IPv6:   ${reset}${green}$ipv6${reset}"
[[ $security != "none" ]] && echo -e " ${lightpink}证书提示:   ${yellow}客户端需启用 insecure 选项${reset}"

footer
read -p "$(echo -e "${cyan}按回车键返回...${reset}")" -n 1 -r
bash /root/VPN/menu/config_node.sh
