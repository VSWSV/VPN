#!/bin/bash

cyan='\033[1;36m'
yellow='\033[1;33m'
orange='\033[38;5;208m'
lightpink='\033[38;5;218m'
green='\033[1;32m'
red='\033[1;31m'
reset='\033[0m'

# 路径配置
CLOUDFLARED_DIR="/root/.cloudflared"
CERT_FILE="$CLOUDFLARED_DIR/cert.pem"
CFD_BIN="/root/VPN/cloudflared"
CONFIG_FILE="$CLOUDFLARED_DIR/config_info.txt"

show_top_title() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗"
    printf "${orange}%*s🌐 配置隧道-DNS%*s\n" $(( (83 - 14) / 2 )) "" $(( (83 - 14 + 1) / 2 )) ""
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

show_bottom_line() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

warning() {
    echo -e "\033[38;5;226m⚠️ $1${reset}"
}

info() {
    echo -e "${yellow}🔹 $1${reset}"
}

success() {
    echo -e "${lightpink}✅ $1${reset}"
}

error() {
    echo -e "${red}❌ $1${reset}"
}

validate_email() {
    [[ "$1" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_domain() {
    [[ "$1" =~ ^([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$ ]]
}

check_config_and_cert() {
    mkdir -p "$CLOUDFLARED_DIR"
    chmod 700 "$CLOUDFLARED_DIR"

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
        echo
        
        while true; do
            read -p "$(echo -e "${yellow}是否删除现有配置并重新设置？(Y/n): ${reset}")" delchoice
            case "$delchoice" in
                Y|y)
                    TUNNEL_ID=$(grep "隧道ID：" "$CONFIG_FILE" | awk -F '：' '{print $2}')
                    rm -f "$CONFIG_FILE"
                    [[ -n "$TUNNEL_ID" ]] && rm -f "$CLOUDFLARED_DIR/${TUNNEL_ID}.json"
                    success "已删除旧配置文件及对应隧道 JSON：$TUNNEL_ID"
                    break ;;
                N|n)
                    info "保留现有配置，继续执行"
                    break ;;
                *)
                    error "无效输入，请输入 Y/y 或 N/n"
                    ;;
            esac
        done
    fi

    if [[ -f "$CERT_FILE" ]]; then
        info "检测到残留的 Cloudflare 授权证书：$CERT_FILE"
        while true; do
            read -p "$(echo -e "${yellow}是否删除旧证书？(Y/n): ${reset}")" certchoice
            case "$certchoice" in
                Y|y)
                    rm -f "$CERT_FILE"
                    success "已删除旧 Cloudflare 授权证书"
                    break ;;
                N|n)
                    info "保留旧证书，继续执行"
                    break ;;
                *) 
                    error "无效输入，请输入 Y/y 或 N/n"
                    ;;
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

input_info() {
    if [[ -f "$CONFIG_FILE" ]]; then
        info "📝 正在读取现有配置（绿色为当前值，直接回车即可保留）："
        
        CURRENT_CF_EMAIL=$(grep "账户邮箱：" "$CONFIG_FILE" | awk -F '：' '{print $2}')
        CURRENT_CF_API_TOKEN=$(grep "API令牌：" "$CONFIG_FILE" | awk -F '：' '{print $2}')
        CURRENT_CF_ZONE=$(grep "顶级域名：" "$CONFIG_FILE" | awk -F '：' '{print $2}')
        CURRENT_SUB_DOMAIN=$(grep "子域前缀：" "$CONFIG_FILE" | awk -F '：' '{print $2}')
        CURRENT_TUNNEL_NAME=$(grep "隧道名称：" "$CONFIG_FILE" | awk -F '：' '{print $2}')
        CURRENT_TUNNEL_ID=$(grep "隧道ID：" "$CONFIG_FILE" | awk -F '：' '{print $2}')
        
        prompt_default() {
            echo -ne "${yellow}$1 [${green}$2${yellow}]: ${reset}"
        }
    else
        info "📝 请输入 Cloudflare 配置信息："
        
        prompt_default() {
            echo -ne "${yellow}$1: ${reset}"
        }
    fi

    while true; do
        prompt_default "📧 账户邮箱" "${CURRENT_CF_EMAIL:-}"
        read -r CF_EMAIL
        CF_EMAIL=${CF_EMAIL:-$CURRENT_CF_EMAIL}
        info "输入为：${green}$CF_EMAIL${reset}"
        validate_email "$CF_EMAIL" && break || error "邮箱格式无效，请重新输入。"
    done

    while true; do
        prompt_default "🔑 API 令牌" "${CURRENT_CF_API_TOKEN:-}"
        read -r CF_API_TOKEN
        CF_API_TOKEN=${CF_API_TOKEN:-$CURRENT_CF_API_TOKEN}
        info "输入为：${green}$CF_API_TOKEN${reset}"
        [[ -n "$CF_API_TOKEN" ]] && break || error "API 令牌不能为空，请重新输入。"
    done

    while true; do
        prompt_default "🌐 顶级域名" "${CURRENT_CF_ZONE:-}"
        read -r CF_ZONE
        CF_ZONE=${CF_ZONE:-$CURRENT_CF_ZONE}
        info "输入为：${green}$CF_ZONE${reset}"
        validate_domain "$CF_ZONE" && break || error "顶级域名格式无效，请重新输入。"
    done

    while true; do
        prompt_default "🔖 子域名前缀" "${CURRENT_SUB_DOMAIN:-}"
        read -r SUB_DOMAIN
        SUB_DOMAIN=${SUB_DOMAIN:-$CURRENT_SUB_DOMAIN}
        info "输入为：${green}$SUB_DOMAIN${reset}"
        [[ "$SUB_DOMAIN" =~ ^[a-zA-Z0-9-]+$ ]] && break || error "子域名前缀无效，只能包含字母、数字和连字符。"
    done

    while true; do
        prompt_default "🚇 隧道名称" "${CURRENT_TUNNEL_NAME:-}"
        read -r TUNNEL_NAME
        TUNNEL_NAME=${TUNNEL_NAME:-$CURRENT_TUNNEL_NAME}
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
      [[ -n "$CURRENT_TUNNEL_ID" ]] && echo "隧道ID：$CURRENT_TUNNEL_ID"
    } > "$CONFIG_FILE"
}

check_dns_record() {
    local record_type=$1
    local record_name=$2
    local content=$3
    
    existing_record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=$record_type&name=$record_name" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")
        
    if echo "$existing_record" | jq -e '.result[0]' >/dev/null; then
        info "检测到已存在的${record_type}记录："
        echo -e "${lightpink}├─ 记录名: ${green}$record_name${reset}"
        echo -e "${lightpink}├─ 记录值: ${green}$(echo "$existing_record" | jq -r '.result[0].content')${reset}"
        echo -e "${lightpink}└─ 记录ID: ${green}$(echo "$existing_record" | jq -r '.result[0].id')${reset}"
        
        while true; do
            read -p "$(echo -e "${yellow}是否删除并重建此记录？(Y/n): ${reset}")" choice
            case "$choice" in
                Y|y)
                    record_id=$(echo "$existing_record" | jq -r '.result[0].id')
                    delete_result=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
                        -H "Authorization: Bearer $CF_API_TOKEN" \
                        -H "Content-Type: application/json")
                    if echo "$delete_result" | grep -q '"success":true'; then
                        success "记录删除成功"
                        return 0
                    else
                        error "记录删除失败"
                        return 1
                    fi ;;
                N|n)
                    info "将使用现有${record_type}记录继续操作"
                    return 1 ;;
                *)
                    error "无效输入，请输入 Y/y 或 N/n" ;;
            esac
        done
    else
        return 0
    fi
}

create_dns_records() {
    info "📡 开始处理 DNS 记录..."
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CF_ZONE" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')

    if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
        error "获取 Zone ID 失败，请检查："
        error "1. 域名是否正确"
        error "2. API令牌权限是否足够"
        return 1
    fi

    # 处理A记录
    if check_dns_record "A" "@" "$IPV4"; then
        A_RECORD=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"@\",\"content\":\"$IPV4\",\"ttl\":1,\"proxied\":false}")
        echo "$A_RECORD" | grep -q '"success":true' && success "A记录创建成功" || error "A记录创建失败"
    fi

    # 处理AAAA记录
    if check_dns_record "AAAA" "@" "$IPV6"; then
        AAAA_RECORD=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"AAAA\",\"name\":\"@\",\"content\":\"$IPV6\",\"ttl\":1,\"proxied\":false}")
        echo "$AAAA_RECORD" | grep -q '"success":true' && success "AAAA记录创建成功" || error "AAAA记录创建失败"
    fi
}

authorize_and_create_tunnel() {
    # 处理证书冲突
    if [[ -f "$CERT_FILE" ]]; then
        read -p "$(echo -e "${yellow}检测到已有证书文件，是否删除后重新登录？(Y/n): ${reset}")" cert_choice
        if [[ "$cert_choice" =~ ^[Yy]$ ]]; then
            rm -f "$CERT_FILE"
            info "已删除旧证书，准备重新登录..."
        fi
    fi

    info "🧩 开始 Cloudflare 隧道授权..."
    if ! $CFD_BIN tunnel login; then
        error "授权失败，请检查："
        error "1. 网络连接是否正常"
        error "2. 账户邮箱和API令牌是否正确"
        exit 1
    fi

    success "授权成功，使用证书路径：${green}$CERT_FILE${reset}"

    # 处理隧道已存在的情况
    if $CFD_BIN tunnel list | grep -q "$TUNNEL_NAME"; then
        while true; do
            read -p "$(echo -e "${yellow}隧道 '$TUNNEL_NAME' 已存在，是否删除后重新创建？(Y/n): ${reset}")" recreate
            case "$recreate" in
                Y|y)
                    $CFD_BIN tunnel delete "$TUNNEL_NAME"
                    info "已删除旧隧道，准备重新创建..."
                    break ;;
                N|n)
                    info "使用现有隧道继续操作..."
                    TUNNEL_ID=$($CFD_BIN tunnel list | awk -v name="$TUNNEL_NAME" '$2 == name {print $1}')
                    return 0 ;;
                *)
                    error "无效输入，请输入 Y/y 或 N/n" ;;
            esac
        done
    fi

    # 创建隧道
    info "正在创建隧道: ${green}$TUNNEL_NAME${reset}"
    if ! $CFD_BIN tunnel create "$TUNNEL_NAME"; then
        error "隧道创建失败，请检查："
        error "1. 隧道名称是否唯一"
        error "2. Cloudflare账户权限"
        exit 1
    fi

    TUNNEL_ID=$($CFD_BIN tunnel list | awk -v name="$TUNNEL_NAME" '$2 == name {print $1}')
    [[ -z "$TUNNEL_ID" ]] && { error "未获取到隧道ID"; exit 1; }

    success "隧道创建成功，ID: ${green}$TUNNEL_ID${reset}"
    echo "隧道ID：$TUNNEL_ID" >> "$CONFIG_FILE"
}

create_cname_record() {
    info "🔗 正在处理 CNAME 记录..."
    if check_dns_record "CNAME" "$SUB_DOMAIN" "$TUNNEL_ID.cfargotunnel.com"; then
        CNAME_RESULT=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"CNAME\",\"name\":\"$SUB_DOMAIN\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")
        
        if echo "$CNAME_RESULT" | grep -q '"success":true'; then
            success "CNAME记录创建成功: ${green}$SUB_DOMAIN.$CF_ZONE → $TUNNEL_ID.cfargotunnel.com${reset}"
        else
            error "CNAME记录创建失败"
            error "响应结果: $CNAME_RESULT"
        fi
    fi
}

final_info() {
    info "📦 所有步骤已完成，以下为生成的配置信息："
    echo -e "${lightpink}账户邮箱：${green}$CF_EMAIL${reset}"
    echo -e "${lightpink}API 令牌：${green}$CF_API_TOKEN${reset}"
    echo -e "${lightpink}顶级域名：${green}$CF_ZONE${reset}"
    echo -e "${lightpink}子域名前缀：${green}$SUB_DOMAIN${reset}"
    echo -e "${lightpink}隧道名称：${green}$TUNNEL_NAME${reset}"
    [[ -n "$TUNNEL_ID" ]] && echo -e "${lightpink}隧道ID：${green}$TUNNEL_ID${reset}"
    echo -e "${lightpink}公网 IPv4：${green}$IPV4${reset}"
    echo -e "${lightpink}公网 IPv6：${green}$IPV6${reset}"
    echo -e "${lightpink}证书路径：${green}$CERT_FILE${reset}"

    echo -e "\n${green}🚀 启动隧道命令：${reset}"
    echo -e "${cyan}$CFD_BIN tunnel run $TUNNEL_NAME${reset}"
    
    echo -e "\n${lightpink}📁 生成的文件：${reset}"
    ls -lh "$CLOUDFLARED_DIR" | grep -E "cert.pem|$TUNNEL_ID.json|config_info.txt" 2>/dev/null
}

main() {
    clear
    show_top_title
    check_config_and_cert
    get_ip_addresses
    input_info
    create_dns_records || return 1
    authorize_and_create_tunnel
    create_cname_record
    final_info
    show_bottom_line
    chmod +x "$0"
    read -p "$(echo -e "${yellow}按回车键返回主菜单...${reset}")" dummy
    bash "/root/VPN/menu/config_node.sh"
}

main
