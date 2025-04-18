#!/bin/bash

cyan='\033[1;36m'
yellow='\033[1;33m'
orange='\033[38;5;208m'
lightpink='\033[38;5;218m'
reset='\033[0m'

VPN_DIR="/root/VPN"
XRAY_BIN="$VPN_DIR/xray/xray"
XRAY_CONF="$VPN_DIR/xray/config.json"
HYSTERIA_BIN="$VPN_DIR/hysteria"
HYSTERIA_CONF="$VPN_DIR/hysteria.yaml"
CFD_BIN="$VPN_DIR/cloudflared"

CONFIG_DIR="$VPN_DIR"
CONFIG_FILE="$CONFIG_DIR/config_info.txt"

show_header() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗"
    printf "${orange}║%*s配置隧道 - DNS%*s║\n" $(( (83 - 18) / 2 )) "" $(( (83 - 18 + 1) / 2 )) ""
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

show_footer() {
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

check_prev_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        show_header
        info "检测到已有配置文件：$CONFIG_FILE"
        info "生成时间：$(stat -c %y $CONFIG_FILE)"
        cat "$CONFIG_FILE"
        show_footer
        read -p "是否覆盖现有配置？(Y/n): " choice
        if [[ $choice == [Yy] ]]; then
            info "删除旧配置..."
            rm -rf "$CONFIG_DIR"/*
        else
            info "返回主菜单..."
            bash "$VPN_DIR/menu/config_node.sh"
            exit 0
        fi
    fi
}

get_ip_addresses() {
    IPV4=$(curl -s4 ifconfig.co)
    IPV6=$(curl -s6 ifconfig.co)

    info "📶 当前公网 IPv4：$IPV4"
    info "📶 当前公网 IPv6：$IPV6"
}

validate_email() {
    [[ "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_domain() {
    [[ "$1" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]
}

input_info() {
    show_header
    info "📝 请输入 Cloudflare 配置信息："

    while true; do
        read -p "📧 账户邮箱: " CF_EMAIL
        info "输入为：$CF_EMAIL"
        validate_email "$CF_EMAIL" && break || error "邮箱格式无效，请重新输入。"
    done

    while true; do
        read -p "🔑 API 令牌: " CF_API_TOKEN
        info "输入为：$CF_API_TOKEN"
        [[ -n "$CF_API_TOKEN" ]] && break || error "API 令牌不能为空，请重新输入。"
    done

    while true; do
        read -p "🌐 顶级域名 (如 example.com): " CF_ZONE
        info "输入为：$CF_ZONE"
        validate_domain "$CF_ZONE" && break || error "顶级域名格式无效，请重新输入。"
    done

    while true; do
        read -p "🔖 子域名前缀 (如 node1): " SUB_DOMAIN
        info "输入为：$SUB_DOMAIN"
        [[ "$SUB_DOMAIN" =~ ^[a-zA-Z0-9-]+$ ]] && break || error "子域名前缀无效，只能包含字母、数字和连字符。"
    done

    while true; do
        read -p "🚇 隧道名称: " TUNNEL_NAME
        info "输入为：$TUNNEL_NAME"
        [[ "$TUNNEL_NAME" =~ ^[a-zA-Z0-9_-]+$ ]] && break || error "隧道名称无效，只能包含字母、数字、下划线或连字符。"
    done

    info "📋 配置信息确认："
    info "账户邮箱: $CF_EMAIL"
    info "API Token: $CF_API_TOKEN"
    info "顶级域名: $CF_ZONE"
    info "子域名: $SUB_DOMAIN"
    info "隧道名称: $TUNNEL_NAME"

    echo "CF_EMAIL=$CF_EMAIL" > "$CONFIG_FILE"
    echo "CF_API_TOKEN=$CF_API_TOKEN" >> "$CONFIG_FILE"
    echo "CF_ZONE=$CF_ZONE" >> "$CONFIG_FILE"
    echo "SUB_DOMAIN=$SUB_DOMAIN" >> "$CONFIG_FILE"
    echo "TUNNEL_NAME=$TUNNEL_NAME" >> "$CONFIG_FILE"
    echo "IPV4=$IPV4" >> "$CONFIG_FILE"
    echo "IPV6=$IPV6" >> "$CONFIG_FILE"
    show_footer
}

create_dns_records() {
    show_header
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
        --data '{"type":"A","name":"@","content":"'"$IPV4"'","ttl":1,"proxied":false}')

    AAAA_RECORD=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{"type":"AAAA","name":"@","content":"'"$IPV6"'","ttl":1,"proxied":false}')

    echo "$A_RECORD" | grep -q '"success":true' && success "A记录创建成功" || error "A记录创建失败"
    echo "$AAAA_RECORD" | grep -q '"success":true' && success "AAAA记录创建成功" || error "AAAA记录创建失败"
    show_footer
}

authorize_and_create_tunnel() {
    show_header
    info "🧩 开始 Cloudflare 隧道授权..."
    $CFD_BIN tunnel login
    if [[ $? -ne 0 ]]; then
        error "授权失败，请检查 Cloudflared 登录"
        exit 1
    fi
    success "授权成功"

    $CFD_BIN tunnel create "$TUNNEL_NAME"
    if [[ $? -ne 0 ]]; then
        error "隧道创建失败"
        exit 1
    fi

    TUNNEL_ID=$($CFD_BIN tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
    success "隧道 ID：$TUNNEL_ID"

    info "🔗 创建 CNAME 记录..."
    CNAME_RESULT=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"$SUB_DOMAIN\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    echo "$CNAME_RESULT" | grep -q '"success":true' && success "CNAME记录创建成功" || error "CNAME记录创建失败"
    show_footer
}

final_info() {
    show_header
    info "📦 所有步骤已完成，以下为生成的配置信息："
    cat "$CONFIG_FILE"
    show_footer
}

main() {
    check_prev_config
    get_ip_addresses
    input_info
    create_dns_records
    authorize_and_create_tunnel
    final_info
    chmod +x "$0"
}

main
