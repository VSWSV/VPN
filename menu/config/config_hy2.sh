#!/bin/bash

# 颜色定义
cyan="\033[1;36m"; blue="\033[1;34m"; green="\033[1;32m"; yellow="\033[1;33m"
red="\033[1;31m"; orange="\033[38;5;208m"; lightpink="\033[38;5;213m"; white="\033[1;37m"; reset="\033[0m"

# 目录配置
HY2_DIR="/root/VPN/HY2"
CONFIG_PATH="$HY2_DIR/config/hysteria.yaml"
CERTS_DIR="$HY2_DIR/certs"

function header() {
    clear
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
    echo -e "${orange}                              🌈 配置 Hysteria 2 节点                           ${reset}"
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
        alpn) [[ "$2" =~ ^(h2|h3|http/1\.1)$ ]] ;;
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

# 初始化目录
mkdir -p "$HY2_DIR"/{config,certs,logs,pids,client_configs,subscriptions}
chmod 700 "$HY2_DIR" "$HY2_DIR"/{config,certs,logs,pids}

# 主流程
header

# 现有配置检测
if [ -f "$CONFIG_PATH" ]; then
    current_uuid=$(grep "password:" "$CONFIG_PATH" | awk -F'"' '{print $2}')
    current_port=$(grep "listen:" "$CONFIG_PATH" | awk '{print $2}' | tr -d ':')
    current_sni=$(grep "sni:" "$CONFIG_PATH" | awk '{print $2}')
    current_alpn=$(grep -A1 "alpn:" "$CONFIG_PATH" | tail -1 | tr -d ' -')
    current_ipv4=$(curl -s4 ifconfig.co || echo "获取失败")
    current_ipv6=$(curl -s6 ifconfig.co || echo "获取失败")

    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e "${orange}                              📝 当前配置预览                                  ${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    echo -e " ${lightpink}UUID：     ${reset}${green}$current_uuid${reset}"
    echo -e " ${lightpink}端口：     ${reset}${green}$current_port${reset}"
    echo -e " ${lightpink}域名：     ${reset}${green}$current_sni${reset}"
    echo -e " ${lightpink}协议：     ${reset}${green}$current_alpn${reset}"
    echo -e " ${lightpink}IPv4：     ${reset}${green}$current_ipv4${reset}"
    echo -e " ${lightpink}IPv6：     ${reset}${green}$current_ipv6${reset}"
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

    # 询问是否覆盖配置（严格 Y/y 或 N/n）
    while true; do
        read -p "$(echo -e "${yellow}是否覆盖当前配置？(y/N): ${reset}")" -n 1 overwrite
        echo  # 换行
        
        case "$overwrite" in
            [Yy])
                # 用户选择覆盖，继续执行后续配置
                break
                ;;
            [Nn])
                # 用户选择不覆盖，返回菜单
                clear
                bash /root/VPN/menu/config_node.sh
                exit
                ;;
            *)
                # 无效输入，提示并重新询问
                echo -e "${red}❌ 无效输入！${reset}"
                sleep 0.5
                # 清空输入缓冲区，防止残留字符影响
                while read -r -t 0; do read -r; done
                # 重新显示当前配置
                header
                echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
                echo -e " ${lightpink}UUID：     ${reset}${green}$current_uuid${reset}"
                echo -e " ${lightpink}端口：     ${reset}${green}$current_port${reset}"
                echo -e " ${lightpink}域名：     ${reset}${green}$current_sni${reset}"
                echo -e " ${lightpink}协议：     ${reset}${green}$current_alpn${reset}"
                echo -e " ${lightpink}IPv4：     ${reset}${green}$current_ipv4${reset}"
                echo -e " ${lightpink}IPv6：     ${reset}${green}$current_ipv6${reset}"
                echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
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

# ALPN协议
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
read -p "$(echo -e " ${lightpink}⇨ 请输入ALPN协议 [h3]: ${reset}")" alpn
alpn=${alpn:-h3}
show_status "ALPN协议: ${lightpink}$alpn${reset}"

# TLS配置
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e " ${lightpink}⇨ 请选择TLS配置:${reset}"
echo -e "  ${green}① 使用自签名证书 (推荐测试用)${reset}"
echo -e "  ${green}② 使用现有证书${reset}"
echo -e "  ${yellow}③ 禁用TLS (不推荐)${reset}"
read -p "$(echo -e " ${blue}请选择：${reset}")" tls_choice

case $tls_choice in
    1)
        generate_certs "$sni"
        tls_config="  cert: $CERTS_DIR/cert.pem
  key: $CERTS_DIR/private.key
  sni: $sni
  alpn:
    - $alpn"
        ;;
    2)
        while true; do
            read -p "$(echo -e " ${lightpink}⇨ 请输入证书路径: ${reset}")" cert_path
            read -p "$(echo -e " ${lightpink}⇨ 请输入私钥路径: ${reset}")" key_path
            if [ -f "$cert_path" ] && [ -f "$key_path" ]; then
                tls_config="  cert: $cert_path
  key: $key_path
  sni: $sni
  alpn:
    - $alpn"
                break
            else
                show_error "证书文件不存在，请重新输入"
            fi
        done
        ;;
    3)
        tls_config="  enabled: false"
        show_error "警告: 禁用TLS将导致连接不安全!"
        ;;
    *)
        show_error "无效选择，默认使用自签名证书"
        generate_certs "$sni"
        tls_config="  cert: $CERTS_DIR/cert.pem
  key: $CERTS_DIR/private.key
  sni: $sni
  alpn:
    - $alpn"
        ;;
esac

# 生成配置文件
cat > "$CONFIG_PATH" <<EOF
listen: :$port
protocol: hysteria2
auth:
  type: password
  password: "$uuid"
tls:
$tls_config
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
echo -e " ${lightpink}认证密码:   ${reset}${green}$uuid${reset}"
echo -e " ${lightpink}加密协议:   ${reset}${green}$alpn${reset}"
echo -e " ${lightpink}公网IPv4:   ${reset}${green}$ipv4${reset}"
echo -e " ${lightpink}公网IPv6:   ${reset}${green}$ipv6${reset}"
[ $tls_choice -eq 1 ] && echo -e " ${lightpink}证书提示:   ${yellow}客户端需启用 insecure 选项${reset}"

footer
read -p "$(echo -e "${white}按任意键返回主菜单...${reset}")" -n 1
bash /root/VPN/menu/config_node.sh
