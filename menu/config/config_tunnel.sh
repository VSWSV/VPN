#!/bin/bash
clear
# 颜色定义
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
CONFIG_YML="$CLOUDFLARED_DIR/config.yml"

# 显示顶部标题
show_top_title() {
    echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗"
    printf "${orange}%*s🌐 配置隧道-DNS%*s\n" $(( (83 - 14) / 2 )) "" $(( (83 - 14 + 1) / 2 )) ""
    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

show_bottom_line() {
    echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

info() { echo -e "${yellow}🔹 $1${reset}"; }
success() { echo -e "${lightpink}✅ $1${reset}"; }
error() { echo -e "${red}❌ $1${reset}"; }
warning() { echo -e "\033[38;5;226m⚠️ $1${reset}"; }

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
        [[ -f "$CONFIG_YML" ]] && printf "${lightpink}%-15s${reset}${green}%s${reset}\n" "配置文件：" "$CONFIG_YML"
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
            read -p "$(echo -e "${yellow}❓ 是否删除现有配置并重新设置？(Y/n): ${reset}")" delchoice
            case "$delchoice" in
                Y|y)
                    rm -f "$CONFIG_FILE" "$CONFIG_YML"
                    info "🧹 开始清理非证书文件（保留 *.pem）..."
                    deleted_files=$(find "$CLOUDFLARED_DIR" -type f ! -name "*.pem")
                    if [[ -n "$deleted_files" ]]; then
                        while IFS= read -r file; do
                            rm -f "$file"
                            echo -e "${red}🗑️ 已删除：${reset}${file}"
                        done <<< "$deleted_files"
                        success " 非证书文件清理完成"
                    else
                        warning " 未找到需删除的非证书文件"
                    fi
                    success " 已删除旧配置文件并完成隧道文件清理"
                    break ;;
                N|n)
                    info " 保留现有配置，继续执行"
                    break ;;
                *)
                    error " 无效输入，请输入 Y/y 或 N/n" ;;
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
        CURRENT_PORT=$(grep "本地端口：" "$CONFIG_FILE" | awk -F '：' '{print $2}')
        prompt_default() { echo -ne "${yellow}$1 [${green}$2${yellow}]: ${reset}"; }
    else
        info "📝 请输入 Cloudflare 配置信息："
        prompt_default() { echo -ne "${yellow}$1: ${reset}"; }
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

    # 端口号处理 - 现在与其他配置项一致
    if [[ -n "$CURRENT_PORT" ]]; then
        DEFAULT_PORT="$CURRENT_PORT"
    else
        for i in {1..20}; do
            rand_port=$((RANDOM % 10000 + 20000))
            if ! lsof -i:"$rand_port" &>/dev/null; then
                DEFAULT_PORT="$rand_port"
                break
            fi
        done
        [[ -z "$DEFAULT_PORT" ]] && { error "无法生成可用端口，请检查端口占用"; return 1; }
    fi

    while true; do
        prompt_default "🔌 本地端口" "${DEFAULT_PORT:-}"
        read -r custom_port
        if [[ -z "$custom_port" ]]; then
            PORT="$DEFAULT_PORT"
            info "输入为：${green}使用默认端口 $PORT${reset}"
            break
        elif [[ "$custom_port" =~ ^[0-9]+$ ]] && ((custom_port >= 1 && custom_port <= 65535)); then
            if ! lsof -i:"$custom_port" &>/dev/null; then
                PORT="$custom_port"
                info "输入为：${green}$PORT${reset}"
                break
            else
                warning "端口 ${custom_port} 被占用，请重新输入"
            fi
        else
            warning "输入无效，请输入 1~65535 的端口号"
        fi
    done

    info "📋 配置信息确认："
    info "账户邮箱: ${green}$CF_EMAIL${reset}"
    info "API Token: ${green}$CF_API_TOKEN${reset}"
    info "顶级域名: ${green}$CF_ZONE${reset}"
    info "子域名: ${green}${SUB_DOMAIN}.${CF_ZONE}${reset}"
    info "隧道名称: ${green}$TUNNEL_NAME${reset}"
    info "本地端口: ${green}$PORT${reset}"

    {
        echo "账户邮箱：$CF_EMAIL"
        echo "API令牌：$CF_API_TOKEN"
        echo "顶级域名：$CF_ZONE"
        echo "子域前缀：$SUB_DOMAIN"
        echo "隧道名称：$TUNNEL_NAME"
        echo "本地端口：$PORT"
        echo "公网 IPv4：$IPV4"
        echo "公网 IPv6：$IPV6"
        echo "证书路径：$CERT_FILE"
        [[ -n "$CURRENT_TUNNEL_ID" ]] && echo "隧道ID：$CURRENT_TUNNEL_ID"
    } > "$CONFIG_FILE"
    check_root_dns_records
}

check_root_dns_records() {
    local ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CF_ZONE" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')

    [[ "$ZONE_ID" == "null" || -z "$ZONE_ID" ]] && { error "获取 Zone ID 失败"; return; }

    echo -e "\n${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

    for record_type in A AAAA; do
        local record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=$record_type&name=$CF_ZONE" \
            -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")
        if echo "$record" | jq -e '.result[0]' >/dev/null; then
            local content=$(echo "$record" | jq -r '.result[0].content')
            echo -e "${lightpink}✅ ${record_type}记录存在：${green}$CF_ZONE → $content${reset}"
        else
            echo -e "${yellow}⚠️ ${record_type}记录不存在：${green}$CF_ZONE${reset}"
        fi
    done

    echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}\n"
}

handle_dns_record() {
    local record_type=$1
    local record_name=$2
    local content=$3

    [[ "$record_name" == "@" ]] && record_name="$CF_ZONE"

    existing_record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=$record_type&name=$record_name" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")

    if echo "$existing_record" | jq -e '.result[0]' >/dev/null; then
        info "检测到已存在的${record_type}记录："
        echo -e "${lightpink}├─ 记录名: ${green}$record_name${reset}"
        echo -e "${lightpink}└─ 记录值: ${green}$(echo "$existing_record" | jq -r '.result[0].content')${reset}"

        while true; do
            read -p "$(echo -e "${yellow}❓是否删除并重建？(Y/n): ${reset}")" choice
            case "$choice" in
                Y|y)
                    record_id=$(echo "$existing_record" | jq -r '.result[0].id')
                    delete_result=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
                        -H "Authorization: Bearer $CF_API_TOKEN" \
                        -H "Content-Type: application/json")
                    if echo "$delete_result" | grep -q '"success":true'; then
                        success "旧记录删除成功"
                    else
                        error "记录删除失败"
                        return 1
                    fi
                    break ;;
                N|n)
                    success "已保留现有${record_type}记录"
                    return 0 ;;
                *)
                    error "无效输入，请输入 Y/y 或 N/n" ;;
            esac
        done
    fi

    info "正在创建${record_type}记录..."
    create_result=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"$record_type\",\"name\":\"$record_name\",\"content\":\"$content\",\"ttl\":1,\"proxied\":false}")

    if echo "$create_result" | grep -q '"success":true'; then
        success "${record_type}记录创建成功：$record_name → $content"
    else
        error "${record_type}记录创建失败"
        error "响应结果：$(echo "$create_result" | jq -r '.errors[0].message')"
        return 1
    fi
}

create_dns_records() {
    info "📡 开始处理DNS记录..."

    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$CF_ZONE" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')

    [[ "$ZONE_ID" == "null" || -z "$ZONE_ID" ]] && { error "获取Zone ID失败"; return 1; }

    echo && handle_dns_record "A" "@" "$IPV4"
    echo && handle_dns_record "AAAA" "@" "$IPV6"
}

generate_config_yml() {
    cat > "$CONFIG_YML" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CLOUDFLARED_DIR/$TUNNEL_ID.json
logfile: /root/.cloudflared/tunnel.log
ingress:
  - hostname: ${SUB_DOMAIN}.${CF_ZONE}
    service: http://localhost:$PORT
  - service: http_status:404
EOF

    success "📄 已生成配置文件：${green}$CONFIG_YML${reset}"
    info "🚪 隧道将转发至本地端口：${green}$PORT${reset}"
}


handle_tunnel() {
    if [[ ! -f "$CERT_FILE" ]]; then
        warning "未检测到授权证书，准备进行 Cloudflare 授权登录..."
    else
        info "🔐 已检测到授权证书：$CERT_FILE"
        read -p "$(echo -e "${yellow}❓检测到已有证书文件，是否删除后重授权？(Y/n): ${reset}")" cert_choice
        if [[ "$cert_choice" =~ ^[Yy]$ ]]; then
            rm -f "$CERT_FILE"
            info "✅ 已删除旧证书，准备重新登录..."
        fi
    fi

    if [[ ! -f "$CERT_FILE" ]]; then
        info "🧩 开始 Cloudflare 隧道授权..."
        if ! $CFD_BIN tunnel login; then
            error "❌ 授权失败，请检查网络和凭证"
            exit 1
        fi
        success "授权成功，使用证书路径：${green}$CERT_FILE${reset}"
    fi

    if $CFD_BIN tunnel list | grep -q "$TUNNEL_NAME"; then
        TUNNEL_ID=$($CFD_BIN tunnel list | awk -v n="$TUNNEL_NAME" '$2==n{print $1}')
        info "🔍 检测到已存在的隧道："
        echo -e "${lightpink}├─ 隧道名: ${green}$TUNNEL_NAME${reset}"
        echo -e "${lightpink}└─ 隧道ID: ${green}$TUNNEL_ID${reset}"
        while true; do
            read -p "$(echo -e "${yellow}❓是否删除并重建？(Y/n): ${reset}")" choice
            case "$choice" in
                Y|y)
                    $CFD_BIN tunnel delete "$TUNNEL_NAME" >/dev/null 2>&1
                    if [ $? -eq 0 ]; then
                        success "旧隧道删除成功"
                    else
                        error "隧道删除失败"
                        return 1
                    fi
                    break ;;
                N|n)
                    success "已使用现有隧道"
                    TUNNEL_ID=$($CFD_BIN tunnel list | awk -v n="$TUNNEL_NAME" '$2==n{print $1}')
                    return 0 ;;
                *) error "无效输入，请输入 Y/y 或 N/n" ;;
            esac
        done
    fi

    info "🚧 正在创建隧道..."
    if $CFD_BIN tunnel create "$TUNNEL_NAME" >/dev/null 2>&1; then
        success "隧道创建成功"
        TUNNEL_ID=$($CFD_BIN tunnel list | awk -v n="$TUNNEL_NAME" '$2==n{print $1}')
        echo "隧道ID：$TUNNEL_ID" >> "$CONFIG_FILE"
    else
        error "隧道创建失败"
        return 1
    fi

    generate_config_yml
}

handle_cname_record() {
    info "🔗 正在处理CNAME记录..."

    local cname_full="${SUB_DOMAIN}.${CF_ZONE}"
    cname_full="${cname_full%.}"

    existing_cname=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=CNAME&name=$cname_full" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")

    if echo "$existing_cname" | jq -e '.result[0]' >/dev/null; then
        info "检测到已存在的CNAME记录："
        echo -e "${lightpink}├─ 记录名: ${green}$cname_full${reset}"
        echo -e "${lightpink}└─ 记录值: ${green}$(echo "$existing_cname" | jq -r '.result[0].content')${reset}"

        while true; do
            read -p "$(echo -e "${yellow}是否删除并重建？(Y/n): ${reset}")" choice
            case "$choice" in
                Y|y)
                    record_id=$(echo "$existing_cname" | jq -r '.result[0].id')
                    delete_result=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
                        -H "Authorization: Bearer $CF_API_TOKEN" \
                        -H "Content-Type: application/json")
                    if echo "$delete_result" | grep -q '"success":true'; then
                        success "旧记录删除成功"
                    else
                        error "记录删除失败"
                        return 1
                    fi
                    break ;;
                N|n)
                    success "已保留现有CNAME记录"
                    return 0 ;;
                *) error "无效输入，请输入 Y/y 或 N/n" ;;
            esac
        done
    fi

    info "正在创建CNAME记录..."
    create_result=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"$cname_full\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")

    if echo "$create_result" | grep -q '"success":true'; then
        success "CNAME记录创建成功：${green}$cname_full → $TUNNEL_ID.cfargotunnel.com${reset}"
    else
        error "CNAME记录创建失败"
        error "错误信息：$(echo "$create_result" | jq -r '.errors[0].message')"
        return 1
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
    echo -e "${lightpink}本地端口：${green}$PORT${reset}"
    echo -e "${lightpink}证书路径：${green}$CERT_FILE${reset}"
    echo -e "${lightpink}配置文件：${green}$CONFIG_YML${reset}"
    
    echo -e "\n${green}🚀 启动隧道命令：${reset}"
    echo
    echo -e "${cyan}$CFD_BIN tunnel run $TUNNEL_NAME${reset}"

    echo -e "\n${lightpink}📁 生成的文件：${reset}"
    ls -lh "$CLOUDFLARED_DIR" | grep -E "cert.pem|$TUNNEL_ID.json|config_info.txt|config.yml" 2>/dev/null
}

main() {
    clear
    show_top_title
    check_config_and_cert
    get_ip_addresses
    input_info

    echo -e "\n${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    create_dns_records

    echo -e "\n${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    handle_tunnel

    echo -e "\n${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
    handle_cname_record

    final_info
    show_bottom_line
    chmod +x "$0"
    read -p "$(echo -e "💬${cyan}按回车键返回...${reset}")" dummy
    bash "/root/VPN/menu/config_node.sh"
}

main
