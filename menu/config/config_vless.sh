#!/bin/bash

# 颜色定义
cyan="\033[1;36m"; green="\033[1;32m"; yellow="\033[1;33m"
red="\033[1;31m"; lightpink="\033[38;5;213m"; reset="\033[0m"

# 目录配置
VLESS_DIR="/root/VPN/VLESS"
CONFIG_PATH="$VLESS_DIR/config/vless.json"
CERTS_DIR="$VLESS_DIR/certs"

function header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${cyan}                              🌐 配置 VLESS 节点参数                             ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

function validate_input() {
    case $1 in
        uuid) [[ "$2" =~ ^[0-9a-fA-F-]{36}$ ]] ;;
        port) [[ "$2" =~ ^[0-9]{2,5}$ ]] && [ "$2" -ge 1 ] && [ "$2" -le 65535 ] ;;
        domain) [[ "$2" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] ;;
        alpn) [[ "$2" =~ ^(h2|h3|http/1\.1)$ ]] ;;
    esac
}

function generate_certs() {
    echo -e "${yellow}🔄 正在为 $1 生成自签名证书...${reset}"
    mkdir -p "$CERTS_DIR"
    openssl ecparam -genkey -name prime256v1 -out "$CERTS_DIR/private.key"
    openssl req -x509 -new -key "$CERTS_DIR/private.key" -out "$CERTS_DIR/cert.pem" \
        -days 365 -subj "/CN=$1"
    chmod 600 "$CERTS_DIR/"{cert.pem,private.key}
    echo -e "${green}✔️ 证书已生成到 $CERTS_DIR${reset}"
}

function show_current_config() {
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${cyan}                              🌐 当前 VLESS 节点配置预览                         ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e " ${lightpink}UUID：     ${reset}${green}$1${reset}"
    echo -e " ${lightpink}端口号：   ${reset}${green}$2${reset}"
    echo -e " ${lightpink}SNI 域名： ${reset}${green}$3${reset}"
    echo -e " ${lightpink}ALPN 协议：${reset}${green}$4${reset}"
    echo -e " ${lightpink}IPv4：     ${reset}${green}$5${reset}"
    echo -e " ${lightpink}IPv6：     ${reset}${green}$6${reset}"
}

# 初始化目录结构
mkdir -p "$VLESS_DIR"/{config,certs,logs,pids,client_configs,subscriptions}
chmod 700 "$VLESS_DIR" "$VLESS_DIR"/{config,certs,logs,pids}

clear
header

# 现有配置检测
if [ -f "$CONFIG_PATH" ]; then
    echo -e "${yellow}⚠️ 检测到现有配置:${reset}"
    current_uuid=$(jq -r '.inbounds[0].settings.clients[0].id' "$CONFIG_PATH" 2>/dev/null || echo "获取失败")
    current_port=$(jq -r '.inbounds[0].port' "$CONFIG_PATH" 2>/dev/null || echo "获取失败")
    current_sni=$(jq -r '.inbounds[0].streamSettings.tlsSettings.serverName' "$CONFIG_PATH" 2>/dev/null || echo "未设置")
    current_alpn=$(jq -r '.inbounds[0].streamSettings.tlsSettings.alpn[0]' "$CONFIG_PATH" 2>/dev/null || echo "h3")
    current_ipv4=$(curl -s4 ifconfig.co || echo "获取失败")
    current_ipv6=$(curl -s6 ifconfig.co || echo "获取失败")
    
    show_current_config "$current_uuid" "$current_port" "$current_sni" "$current_alpn" "$current_ipv4" "$current_ipv6"
    
    read -p "$(echo -e "\n${yellow}是否覆盖现有配置？(y/N): ${reset}")" -n 1 overwrite
    [[ ! $overwrite =~ ^[Yy]$ ]] && footer && exit 0
fi

# 用户输入
while true; do
    read -p "$(echo -e "\n${cyan}请输入监听端口 [443]: ${reset}")" port
    port=${port:-443}
    if validate_input "port" "$port"; then
        if ! ss -tuln | grep -q ":$port "; then
            break
        else
            echo -e "${red}❌ 端口已被占用，请重新输入${reset}"
        fi
    else
        echo -e "${red}❌ 无效端口号${reset}"
    fi
done

uuid=$(cat /proc/sys/kernel/random/uuid)
echo -e "${green}✔️ 自动生成UUID: ${lightpink}$uuid${reset}"

while true; do
    read -p "$(echo -e "${cyan}请输入SNI域名 (必需): ${reset}")" sni
    if validate_input "domain" "$sni"; then break; fi
    echo -e "${red}❌ 无效域名格式${reset}"
done

read -p "$(echo -e "${cyan}请输入ALPN协议 [h3]: ${reset}")" alpn
alpn=${alpn:-h3}

# TLS配置选项
echo -e "\n${cyan}请选择TLS配置:${reset}"
echo "1) 使用自签名证书 (自动生成)"
echo "2) 使用现有证书 (手动指定路径)"
echo "3) 禁用TLS (不推荐)"
read -p "选择 [1-3]: " tls_choice

case $tls_choice in
    1)
        generate_certs "$sni"
        tls_config='"tlsSettings": {
      "serverName": "'$sni'",
      "alpn": ["'$alpn'"],
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
            read -p "$(echo -e "${cyan}请输入证书路径: ${reset}")" cert_path
            read -p "$(echo -e "${cyan}请输入私钥路径: ${reset}")" key_path
            [ -f "$cert_path" ] && [ -f "$key_path" ] && break
            echo -e "${red}❌ 证书文件不存在，请重新输入${reset}"
        done
        tls_config='"tlsSettings": {
      "serverName": "'$sni'",
      "alpn": ["'$alpn'"],
      "certificates": [
        {
          "certificateFile": "'$cert_path'",
          "keyFile": "'$key_path'"
        }
      ]
    }'
        ;;
    3)
        tls_config='"security": "none"'
        ;;
    *)
        echo -e "${red}❌ 无效选择，默认使用自签名证书${reset}"
        generate_certs "$sni"
        tls_config='"tlsSettings": {
      "serverName": "'$sni'",
      "alpn": ["'$alpn'"],
      "certificates": [
        {
          "certificateFile": "'$CERTS_DIR/cert.pem'",
          "keyFile": "'$CERTS_DIR/private.key'"
        }
      ]
    }'
        ;;
esac

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
            "flow": "xtls-rprx-vision"
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
echo -e "\n${green}✅ 配置已保存到: ${lightpink}$CONFIG_PATH${reset}"

# 显示网络信息
ipv4=$(curl -s4 ifconfig.co || echo "获取失败")
ipv6=$(curl -s6 ifconfig.co || echo "获取失败")
echo -e "\n${yellow}📶 当前网络信息:${reset}"
echo -e "  ${lightpink}IPv4: ${green}$ipv4${reset}"
echo -e "  ${lightpink}IPv6: ${green}$ipv6${reset}"

# 显示客户端配置提示
echo -e "\n${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "${cyan}                              📋 客户端配置指引                                  ${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e "${green}🔗 连接地址: ${lightpink}$sni:$port${reset}"
echo -e "${green}🔑 UUID: ${lightpink}$uuid${reset}"
echo -e "${green}🔐 传输协议: ${lightpink}TCP${reset}"
echo -e "${green}🔒 加密方式: ${lightpink}XTLS${reset}"
[ $tls_choice -eq 1 ] && echo -e "${yellow}⚠️ 注意: 使用自签名证书需在客户端启用 insecure 选项${reset}"
echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

footer
read -p "$(echo -e "${cyan}按任意键返回...${reset}")" -n 1
bash /root/VPN/menu/config_node.sh
