#!/bin/bash

cyan='\033[1;36m'
yellow='\033[1;33m'
orange='\033[38;5;208m'
lightpink='\033[38;5;218m'
green='\033[1;32m'
reset='\033[0m'

VPN_DIR="/root/VPN"
CERT_FILE="$VPN_DIR/cert.pem"
XRAY_BIN="$VPN_DIR/xray/xray"
XRAY_CONF="$VPN_DIR/xray/config.json"
HYSTERIA_BIN="$VPN_DIR/hysteria"
HYSTERIA_CONF="$VPN_DIR/hysteria.yaml"
CFD_BIN="$VPN_DIR/cloudflared"

CONFIG_DIR="$VPN_DIR"
CONFIG_FILE="$CONFIG_DIR/config_info.txt"

show_top_title() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗"
    printf "${orange}%*s🌐 配置隧道-DNS%*s\n" $(( (83 - 14) / 2 )) "" $(( (83 - 14 + 1) / 2 )) ""
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

show_bottom_line() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

info() {
    echo -e "${yellow}🔹 $1${reset}"
}

success() {
    echo -e "${lightpink}✅ $1${reset}"
}

error() {
    echo -e "\033[1;31m❌ $1${reset}"
}

check_config_and_cert() {
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${yellow}🔹 检测到已有配置文件：${reset}"
        printf "${lightpink}%-15s${reset}${green}%s${reset}\n" "文件路径：" "$CONFIG_FILE"
        printf "${lightpink}%-15s${reset}${green}%s${reset}\n" "生成时间：" "$(date -r "$CONFIG_FILE" '+%Y-%m-%d %H:%M:%S')"
        echo -e "${lightpink}配置信息：${reset}"
        
        max_len=0
        while IFS= read -r line; do
            line=${line//:/：}
            key=$(echo "$line" | awk -F '：' '{print $1}')
            key_len=$(echo -n "$key" | awk '{len=0; for(i=1;i<=length($0);i++){c=substr($0,i,1); len+=c~/[\x00-\x7F]/?1:2} print len}')
            (( key_len > max_len )) && max_len=$key_len
        done < "$CONFIG_FILE"
        
        while IFS= read -r line; do
            line=${line//:/：}
            key=$(echo "$line" | awk -F '：' '{print $1}')
            value=$(echo "$line" | awk -F '：' '{print $2}')
            key_len=$(echo -n "$key" | awk '{len=0; for(i=1;i<=length($0);i++){c=substr($0,i,1); len+=c~/[\x00-\x7F]/?1:2} print len}')
            printf "${lightpink}%-$(($max_len+3))s${reset}${green}%s${reset}\n" "${key}：" "$value"
        done < "$CONFIG_FILE"
    fi

    if [[ -f "$CERT_FILE" ]]; then
        info "检测到残留的 Cloudflare 授权证书：$CERT_FILE"
        while true; do
            read -p "是否删除旧证书？(Y/n): " certchoice
            case "$certchoice" in
                Y|y)
                    rm -f "$CERT_FILE"
                    success "已删除旧 Cloudflare 授权证书"
                    break ;;
                N|n)
                    info "保留旧证书，继续执行"
                    break ;;
                *) error "无效输入，请输入 Y/y 或 N/n。" ;;
            esac
        done
    fi
}

get_ip_addresses() {
    IPV4=$(curl -s4 ifconfig.co)
    IPV6=$(curl -s6 ifconfig.co)

    info "📶 当前公网 IPv4：${green}$IPV4${reset}"
    info "📶 当前公网 IPv6：${green}$IPV6${reset}"
}

validate_email() {
    [[ "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_domain() {
    [[ "$1" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]
}

input_info() {
    info "📝 请输入 Cloudflare 配置信息："

    while true; do
        read -p "📧 账户邮箱: " CF_EMAIL
        info "输入为：${green}$CF_EMAIL${reset}"
        validate_email "$CF_EMAIL" && break || error "邮箱格式无效，请重新输入。"
    done

    while true; do
        read -p "🔑 API 令牌: " CF_API_TOKEN
        info "输入为：${green}$CF_API_TOKEN${reset}"
        [[ -n "$CF_API_TOKEN" ]] && break || error "API 令牌不能为空，请重新输入。"
    done

    while true; do
        read -p "🌐 顶级域名: (如 xiaomi.com): " CF_ZONE
        info "输入为：${green}$CF_ZONE${reset}"
        validate_domain "$CF_ZONE" && break || error "顶级域名格式无效，请重新输入。"
    done

    while true; do
        read -p "🔖 子域名前缀: (如 www ): " SUB_DOMAIN
        info "输入为：${green}$SUB_DOMAIN${reset}"
        [[ "$SUB_DOMAIN" =~ ^[a-zA-Z0-9-]+$ ]] && break || error "子域名前缀无效，只能包含字母、数字和连字符。"
    done

    while true; do
        read -p "🚇 隧道名称: " TUNNEL_NAME
        info "输入为：${green}$TUNNEL_NAME${reset}"
        [[ "$TUNNEL_NAME" =~ ^[a-zA-Z0-9_-]+$ ]] && break || error "隧道名称无效，只能包含字母、数字、下划线或连字符。"
    done

    info "📋 配置信息确认："
    info "账户邮箱: ${green}$CF_EMAIL${reset}"
    info "API Token: ${green}$CF_API_TOKEN${reset}"
    info "顶级域名: ${green}$CF_ZONE${reset}"
    info "子域名: ${green}$SUB_DOMAIN${reset}"
    info "隧道名称: ${green}$TUNNEL_NAME${reset}"

    {
      echo "账户邮箱：$CF_EMAIL"
      echo "API令牌：$CF_API_TOKEN"
      echo "顶级域名：$CF_ZONE"
      echo "子域前缀：$SUB_DOMAIN"
      echo "隧道名称：$TUNNEL_NAME"
      echo "公网 IPv4：$IPV4"
      echo "公网 IPv6：$IPV6"
      echo "证书路径：$CERT_FILE"
    } > "$CONFIG_FILE"
}

create_dns_records() {
    info "📡 开始创建 DNS 记录..."
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CF_ZONE" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')

    if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
        error "获取 Zone ID 失败"
        return
    fi

    A_RECORD=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"@\",\"content\":\"$IPV4\",\"ttl\":1,\"proxied\":false}")

    AAAA_RECORD=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"AAAA\",\"name\":\"@\",\"content\":\"$IPV6\",\"ttl\":1,\"proxied\":false}")

    echo "$A_RECORD" | grep -q '"success":true' && success "A记录创建成功" || error "A记录创建失败"
    echo "$AAAA_RECORD" | grep -q '"success":true' && success "AAAA记录创建成功" || error "AAAA记录创建失败"
}

authorize_and_create_tunnel() {
    info "🧩 开始 Cloudflare 隧道授权..."
    $CFD_BIN tunnel login
    if [[ $? -ne 0 ]]; then
        error "授权失败，请检查 Cloudflared 登录"
        exit 1
    fi

    if [[ -f /root/.cloudflared/cert.pem ]]; then
        mv /root/.cloudflared/cert.pem "$CERT_FILE"
        if [[ $? -eq 0 ]]; then
            success "已剪贴授权证书到 ${green}$CERT_FILE${reset}"
        else
            error "剪贴证书失败，请检查权限或路径"
            exit 1
        fi
    else
        error "未找到默认授权证书 /root/.cloudflared/cert.pem"
        exit 1
    fi

    success "授权成功，使用证书路径：${green}$CERT_FILE${reset}"

    TUNNEL_ORIGIN_CERT="$CERT_FILE" $CFD_BIN tunnel create "$TUNNEL_NAME"
    if [[ $? -ne 0 ]]; then
        error "隧道创建失败"
        exit 1
    fi

    TUNNEL_ID=$(TUNNEL_ORIGIN_CERT="$CERT_FILE" $CFD_BIN tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    success "隧道 ID：$TUNNEL_ID"
    echo "隧道ID：$TUNNEL_ID" >> "$CONFIG_FILE"

    # 显式移动凭证文件到 VPN_DIR
    CREDENTIAL_FILE=$(find /root/.cloudflared -name "${TUNNEL_ID}.json" 2>/dev/null)
    if [[ -f "$CREDENTIAL_FILE" ]]; then
        mv "$CREDENTIAL_FILE" "$VPN_DIR/"
        success "隧道凭证已保存到 ${green}$VPN_DIR/${TUNNEL_ID}.json${reset}"
    else
        error "未找到隧道凭证文件 ${TUNNEL_ID}.json"
        exit 1
    fi

    info "🔗 创建 CNAME 记录..."
    CNAME_RESULT=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"$SUB_DOMAIN\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    echo "$CNAME_RESULT" | grep -q '"success":true' && success "CNAME记录创建成功" || error "CNAME记录创建失败"
}

final_info() {
    info "📦 所有步骤已完成，以下为生成的配置信息："
    echo -e "${lightpink}账户邮箱：${green}$CF_EMAIL${reset}"
    echo -e "${lightpink}API 令牌：${green}$CF_API_TOKEN${reset}"
    echo -e "${lightpink}顶级域名：${green}$CF_ZONE${reset}"
    echo -e "${lightpink}子域名前缀：${green}$SUB_DOMAIN${reset}"
    echo -e "${lightpink}隧道名称：${green}$TUNNEL_NAME${reset}"
    echo -e "${lightpink}隧道ID：${green}$TUNNEL_ID${reset}"
    echo -e "${lightpink}公网 IPv4：${green}$IPV4${reset}"
    echo -e "${lightpink}公网 IPv6：${green}$IPV6${reset}"
    echo -e "${lightpink}证书路径：${green}$CERT_FILE${reset}"

    # 直接检查 VPN_DIR 中的凭证文件
    JSON_FILE="$VPN_DIR/${TUNNEL_ID}.json"
    if [[ -f "$JSON_FILE" ]]; then
        success "隧道凭证文件已位于：${green}$JSON_FILE${reset}"
        echo -e "${yellow}👉 启动命令如下：${reset}"
        echo -e "${green}TUNNEL_ORIGIN_CERT=$CERT_FILE $CFD_BIN tunnel run --cred-file $JSON_FILE $TUNNEL_NAME${reset}"
    else
        error "未找到隧道凭证文件 ${TUNNEL_ID}.json，请检查目录：${green}$VPN_DIR${reset}"
    fi
}

main() {
    clear
    show_top_title
    check_config_and_cert
    get_ip_addresses
    input_info
    create_dns_records
    authorize_and_create_tunnel
    final_info
    show_bottom_line
    chmod +x "$0"
    read -p "按回车键返回主菜单..." dummy
    bash "$VPN_DIR/menu/config_node.sh"
}

main
