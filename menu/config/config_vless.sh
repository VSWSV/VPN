#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
clear

# 颜色定义
cyan="\033[1;36m"; blue="\033[1;34m"; green="\033[1;32m"; yellow="\033[1;33m"
red="\033[1;31m"; orange="\033[38;5;208m"; lightpink="\033[38;5;213m"; white="\033[1;37m"; reset="\033[0m"

# 检查依赖
if ! command -v jq &>/dev/null; then
  echo -e "${red}✖ 请先安装 jq 工具：sudo apt install -y jq${reset}"
  exit 1
fi

# 目录配置
VLESS_DIR="/root/VPN/VLESS"
CONFIG_PATH="$VLESS_DIR/config/vless.json"
CERTS_DIR="$VLESS_DIR/certs"

# 捕获 Ctrl+C
trap "echo -e '\n${red}操作已取消！${reset}'; exit 1" SIGINT

function header() {
    clear
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${orange}                              🌈 配置 VLESS 节点               ${reset}"
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
        security) [[ "$2" =~ ^(tls|reality|none)$ ]] ;;
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
    local sni="$1"
    echo -e "${yellow}🛠️  正在为 $sni 生成自签名证书...${reset}"
    mkdir -p "$CERTS_DIR"
    
    if [[ -f "$CERTS_DIR/cert.pem" || -f "$CERTS_DIR/private.key" ]]; then
        read -p "$(echo -e "${yellow}⚠️ 检测到已有证书，是否覆盖？(y/N): ${reset}")" -n 1 overwrite
        echo
        [[ "$overwrite" != [Yy] ]] && return
    fi

    if ! openssl ecparam -genkey -name prime256v1 -out "$CERTS_DIR/private.key" 2>/dev/null; then
        show_error "生成私钥失败！"
        exit 1
    fi
    if ! openssl req -x509 -new -key "$CERTS_DIR/private.key" -out "$CERTS_DIR/cert.pem" \
        -days 365 -subj "/CN=$sni" 2>/dev/null; then
        show_error "生成证书失败！"
        exit 1
    fi
    chmod 600 "$CERTS_DIR/"{cert.pem,private.key}
    show_status "证书已生成到 ${lightpink}$CERTS_DIR${reset}"
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
    current_ipv4=$(curl -4 -s ifconfig.co || echo "获取失败")
    current_ipv6=$(curl -6 -s ifconfig.co || echo "获取失败")

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
    read -p "$(echo -e " ${lightpink}⇨ 请输入SNI域名 (如:example.com): ${reset}")" sni
    if validate_input "domain" "$sni"; then
        show_status "域名设置为: ${lightpink}$sni${reset}"
        break
    else
        show_error "无效域名格式 (示例:example.com)"
    fi
done

# 传输协议配置
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e " ${lightpink}⇨ 请选择传输协议:${reset}"
echo -e "  ${green}① TCP (默认)${reset}"
echo -e "  ${green}② WebSocket (WS)${reset}"
echo -e "  ${green}③ gRPC${reset}"
echo -e "  ${green}④ HTTP/2 (H2)${reset}"
read -p "$(echo -e " ${blue}请选择：${reset}")" transport_choice

case $transport_choice in
    1) 
        network="tcp"
        path=""
        serviceName=""
        ;;
    2)
        network="ws"
        read -p "$(echo -e " ${lightpink}⇨ 请输入WebSocket路径 (默认/vless-ws): ${reset}")" path
        path=${path:-/vless-ws}
        read -p "$(echo -e " ${lightpink}⇨ 请输入Host头 (留空自动使用SNI): ${reset}")" host
        host=${host:-$sni}
        serviceName=""
        ;;
    3)
        network="grpc"
        read -p "$(echo -e " ${lightpink}⇨ 请输入gRPC服务名称 (默认grpc-service): ${reset}")" serviceName
        serviceName=${serviceName:-grpc-service}
        path=""
        ;;
    4)
        network="h2"
        read -p "$(echo -e " ${lightpink}⇨ 请输入HTTP/2路径 (默认/h2-path): ${reset}")" path
        path=${path:-/h2-path}
        serviceName=""
        ;;
    *) 
        network="tcp"
        path=""
        serviceName=""
        ;;
esac

# 安全协议配置
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e " ${lightpink}⇨ 请选择传输安全协议:${reset}"
echo -e "  ${green}① TLS (推荐)${reset}"
echo -e "  ${green}② REALITY (最新技术)${reset}"
echo -e "  ${yellow}③ none (不加密)${reset}"
read -p "$(echo -e " ${blue}请选择：${reset}")" security_choice
case $security_choice in
    1) security="tls" ;;
    2) security="reality" ;;
    3) security="none"; show_error "警告: 禁用加密将导致连接不安全!" ;;
    *) security="tls"; show_error "无效选择，默认使用TLS" ;;
esac

# 协议组合校验（核心修复点）
if [[ "$network" != "tcp" && "$security" == "reality" ]]; then
    show_error "错误: REALITY 仅支持 TCP 传输！"
    exit 1
elif [[ "$network" == "ws" && -n "$flow" ]]; then
    show_error "错误: WebSocket 不能使用 flow 参数！"
    exit 1
elif [[ "$network" == "grpc" && -n "$flow" ]]; then
    show_error "错误: gRPC 不能使用 flow 参数！"
    exit 1
fi

# TLS/REALITY配置
if [[ "$security" != "none" ]]; then
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    
    if [[ "$security" == "reality" ]]; then
        # REALITY配置
        echo -e "${yellow}🛠️  正在配置 REALITY 参数...${reset}"
        read -p "$(echo -e " ${lightpink}⇨ 请输入目标网站 (如:www.google.com): ${reset}")" dest_domain
        read -p "$(echo -e " ${lightpink}⇨ 请输入目标端口 (默认443): ${reset}")" dest_port
        dest_port=${dest_port:-443}
        
        # 生成REALITY密钥对
        echo -e "${yellow}🔑 正在生成REALITY密钥...${reset}"
        reality_keys=$(/root/VPN/xray/xray x25519)
        private_key=$(echo "$reality_keys" | awk '/Private key:/ {print $3}')
        public_key=$(echo "$reality_keys" | awk '/Public key:/ {print $3}')
        
        # 生成shortId
        short_id=$(openssl rand -hex 4)
        
        tls_settings="{
          \"security\": \"reality\",
          \"realitySettings\": {
            \"dest\": \"$dest_domain:$dest_port\",
            \"serverNames\": [\"$sni\"],
            \"privateKey\": \"$private_key\",
            \"publicKey\": \"$public_key\",
            \"shortIds\": [\"$short_id\"]
          }
        }"
    else
        # TLS配置
        echo -e " ${lightpink}⇨ 请选择证书配置:${reset}"
        echo -e "  ${green}① 使用自签名证书 (推荐测试用)${reset}"
        echo -e "  ${green}② 使用现有证书${reset}"
        read -p "$(echo -e " ${blue}请选择：${reset}")" tls_choice
        case $tls_choice in
            1)
                generate_certs "$sni"
                tls_settings="{
                  \"security\": \"tls\",
                  \"tlsSettings\": {
                    \"serverName\": \"$sni\",
                    \"certificates\": [
                      {
                        \"certificateFile\": \"$CERTS_DIR/cert.pem\",
                        \"keyFile\": \"$CERTS_DIR/private.key\"
                      }
                    ]
                  }
                }"
                ;;
            2)
                while true; do
                    read -p "$(echo -e " ${lightpink}⇨ 请输入证书文件绝对路径: ${reset}")" cert_path
                    read -p "$(echo -e " ${lightpink}⇨ 请输入私钥文件绝对路径: ${reset}")" key_path
                    cert_path="${cert_path/#\~/$HOME}"
                    key_path="${key_path/#\~/$HOME}"
                    if [[ -f "$cert_path" && -f "$key_path" ]]; then
                        tls_settings="{
                          \"security\": \"tls\",
                          \"tlsSettings\": {
                            \"serverName\": \"$sni\",
                            \"certificates\": [
                              {
                                \"certificateFile\": \"$cert_path\",
                                \"keyFile\": \"$key_path\"
                              }
                            ]
                          }
                        }"
                        break
                    else
                        [[ ! -f "$cert_path" ]] && show_error "证书文件不存在：$cert_path"
                        [[ ! -f "$key_path" ]] && show_error "私钥文件不存在：$key_path"
                    fi
                done
                ;;
            *)
                show_error "无效选择，默认使用自签名证书"
                generate_certs "$sni"
                tls_settings="{
                  \"security\": \"tls\",
                  \"tlsSettings\": {
                    \"serverName\": \"$sni\",
                    \"certificates\": [
                      {
                        \"certificateFile\": \"$CERTS_DIR/cert.pem\",
                        \"keyFile\": \"$CERTS_DIR/private.key\"
                      }
                    ]
                  }
                }"
                ;;
        esac

        # Cloudflare 支持
        if [[ "$security" == "tls" && "$network" == "ws" ]]; then
            read -p "$(echo -e " ${lightpink}⇨ 是否用于Cloudflare隧道？(y/N): ${reset}")" use_cf
            if [[ "$use_cf" =~ [Yy] ]]; then
                tls_settings=$(echo "$tls_settings" | sed 's/"certificates"/"alpn": ["http\/1.1"],\n      "certificates"/')
                show_status "已启用Cloudflare兼容模式 (ALPN: http/1.1)"
            fi
        fi
    fi
else
    tls_settings='"security": "none"'
fi

# 生成配置文件（严格模式）
case $network in
    "ws")
        stream_settings="{
          \"network\": \"ws\",
          $(echo "$tls_settings" | sed '1d;$d'),
          \"wsSettings\": {
            \"path\": \"${path:-/vless-ws}\",
            \"headers\": {$( [ -n "$host" ] && echo "\"Host\": \"$host\"")}
          }
        }"
        ;;
    "grpc")
        stream_settings="{
          \"network\": \"grpc\",
          $(echo "$tls_settings" | sed '1d;$d'),
          \"grpcSettings\": {
            \"serviceName\": \"${serviceName:-grpc-service}\"
          }
        }"
        ;;
    "h2")
        stream_settings="{
          \"network\": \"h2\",
          $(echo "$tls_settings" | sed '1d;$d'),
          \"httpSettings\": {
            \"path\": \"${path:-/h2-path}\",
            \"host\": [\"$sni\"]
          }
        }"
        ;;
    *)
        stream_settings="{
          \"network\": \"tcp\",
          $tls_settings
        }"
        ;;
esac

config_json="{
  \"inbounds\": [
    {
      \"port\": $port,
      \"protocol\": \"vless\",
      \"settings\": {
        \"clients\": [
          {
            \"id\": \"$uuid\",
            $([ "$network" == "tcp" ] && echo "\"flow\": \"xtls-rprx-vision\",")
            \"level\": 0
          }
        ],
        \"decryption\": \"none\"
      },
      \"streamSettings\": $stream_settings
    }
  ],
  \"outbounds\": [
    {
      \"protocol\": \"freedom\",
      \"settings\": {}
    }
  ]
}"

# 验证并写入配置
if ! jq -e . >/dev/null 2>&1 <<<"$config_json"; then
    show_error "生成的配置文件无效，请检查参数"
    exit 1
fi
echo "$config_json" | jq . > "$CONFIG_PATH"
chmod 600 "$CONFIG_PATH"

# 显示连接信息
ipv4=$(curl -4 -s ifconfig.co || echo "获取失败")
ipv6=$(curl -6 -s ifconfig.co || echo "获取失败")

echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e "${orange}                              🔗 客户端连接信息                                  ${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e "${yellow}📝 复制命令可快速编辑 ▶ ${green}nano /root/VPN/VLESS/config/vless.json${reset}"
echo -e " ${lightpink}服务器地址: ${reset}${green}$sni${reset}"
echo -e " ${lightpink}连接端口:   ${reset}${green}$port${reset}"
echo -e " ${lightpink}用户ID：    ${reset}${green}$uuid${reset}"
echo -e " ${lightpink}传输协议:   ${reset}${green}$network${reset}"
echo -e " ${lightpink}安全协议:   ${reset}${green}$security${reset}"

case $network in
    "ws") echo -e " ${lightpink}WS路径：    ${reset}${green}${path:-/vless-ws}${reset}" ;;
    "grpc") echo -e " ${lightpink}gRPC服务名: ${reset}${green}${serviceName:-grpc-service}${reset}" ;;
    "h2") echo -e " ${lightpink}H2路径：    ${reset}${green}${path:-/h2-path}${reset}" ;;
esac

if [[ "$security" == "reality" ]]; then
    echo -e " ${lightpink}公钥：      ${reset}${green}$public_key${reset}"
    echo -e " ${lightpink}Short ID:   ${reset}${green}$short_id${reset}"
elif [[ "$security" == "tls" && "$tls_choice" == "1" ]]; then
    echo -e " ${lightpink}证书提示:   ${yellow}客户端需启用 insecure 选项${reset}"
fi

echo -e " ${lightpink}公网IPv4:   ${reset}${green}$ipv4${reset}"
echo -e " ${lightpink}公网IPv6:   ${reset}${green}$ipv6${reset}"

footer
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/config_node.sh
