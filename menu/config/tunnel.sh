#!/bin/bash
# Cloudflare Tunnel + DNS Auto-Setup Script

# ===== 颜色与符号定义 =====
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
cyan="\033[1;36m"
orange="\033[38;5;214m"
pink="\033[1;35m"
lightpink="\033[95m"
reset="\033[0m"
# 提示符号
check_mark="${green}✔️${reset}"
cross_mark="${red}❌${reset}"
warn_mark="${yellow}⚠️${reset}"
info_mark="${blue}🔹${reset}"

# ===== 实用函数定义 =====
info() { echo -e "${blue}🔹 $1${reset}"; }
success() { echo -e "${green}✅ $1${reset}"; }
warning() { echo -e "${yellow}⚠️  $1${reset}"; }
error_exit() { echo -e "${red}❌ $1${reset}"; exit 1; }

# 确认退出函数（用户主动中止）
confirm_exit() {
    echo ""
    read -p "$(echo -e "${yellow}确认要退出脚本吗？(y/n): ${reset}")" -n 1 ans
    echo ""
    case "$ans" in
        [yY]) echo -e "${red}❌ 已取消操作${reset}"; exit 0 ;;
        *) echo -e "${cyan}操作继续...${reset}"; return 0 ;;
    esac
}

# 验证函数
validate_port() { [[ $1 =~ ^[0-9]+$ ]] && [ $1 -ge 1024 ] && [ $1 -le 65535 ]; }
validate_domain() { [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]]; }
validate_alpn() { [[ $1 == "h2" || $1 == "h3" || $1 == "http/1.1" ]]; }
validate_uuid() { [[ $1 =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; }
validate_token() { [[ $1 =~ ^[0-9A-Za-z]{37}$ ]]; }  # 严格37位Token校验

# 捕获 Ctrl+C 中断
trap 'echo -e "\n${red}❌ 已取消操作${reset}"; exit 1' INT

# ===== 脚本标题展示 =====
title_width=60
title="☁️ Cloudflare 隧道自动配置脚本"
border_line=$(printf '═%.0s' $(seq 1 $title_width))
echo -e "${cyan}╔${border_line}╗${reset}"
printf "%b║%b%*s%b%b║%b\n" "$cyan" "$reset$orange" $(( (${#border_line} + 2 + ${#title} ) / 2 )) "$title" "$reset" "$cyan" "$reset"
echo -e "${cyan}╚${border_line}╝${reset}"

# 检查 cloudflared 是否已安装
if ! command -v cloudflared &>/dev/null; then
    error_exit "未找到 Cloudflared 可执行文件，请先安装 Cloudflared。"
fi

# 如果已有配置文件存在，提示是否覆盖旧配置
CONFIG_DIR="$HOME/.cloudflared"
CONFIG_FILE="$CONFIG_DIR/config.yml"
if [ -f "$CONFIG_FILE" ]; then
    echo -e "\n${warn_mark} 检测到已存在的隧道配置文件 ${pink}$CONFIG_FILE${reset}"
    # 提示预览旧配置中的隧道信息
    old_tunnel_id=$(grep -E "^tunnel:" "$CONFIG_FILE" 2>/dev/null | awk '{print $2}')
    if [ -n "$old_tunnel_id" ]; then
        echo -e "${cyan}当前隧道 ID: ${lightpink}$old_tunnel_id${reset}"
    fi
    read -p "$(echo -e "${yellow}是否覆盖现有配置并重新创建隧道？(y/n): ${reset}")" -n 1 overwrite_config
    echo ""
    if [[ ! $overwrite_config =~ ^[yY]$ ]]; then
        echo -e "${red}❌ 已取消操作${reset}"
        exit 0
    fi
    echo -e "${green}✔️ 将覆盖旧配置，继续执行...${reset}"
fi

# 创建配置目录（如果不存在）
mkdir -p "$CONFIG_DIR" || error_exit "无法创建配置目录 $CONFIG_DIR"

# ===== Cloudflare API 凭证输入 =====
CF_EMAIL=""
CF_TOKEN=""
while true; do
    echo ""
    # 读取 API Token（全局 API Key）
    read -s -p "$(echo -e "${cyan}请输入 Cloudflare API Token（全局 API Key，37位）: ${reset}")" CF_TOKEN
    echo ""
    [[ "$CF_TOKEN" =~ ^[Qq](uit)?$ ]] && confirm_exit && continue
    if ! validate_token "$CF_TOKEN"; then
        echo -e "${red}❌ 无效的 API Token！请确保为 37 位全局 API 密钥${reset}"
        continue
    fi
    echo -e "${green}✔️  API Token 格式验证通过${reset}"
    # 读取邮箱
    read -p "$(echo -e "${cyan}请输入 Cloudflare 注册邮箱: ${reset}")" CF_EMAIL
    [[ "$CF_EMAIL" =~ ^[Qq](uit)?$ ]] && confirm_exit && continue
    if [[ -z "$CF_EMAIL" || "$CF_EMAIL" != *@*.* ]]; then
        echo -e "${red}❌ 邮箱格式无效，请重新输入${reset}"
        continue
    fi
    echo -e "${green}✔️  已输入邮箱：${lightpink}$CF_EMAIL${reset}"

    # 尝试获取 Zone 列表
    info "📋 正在获取域名 Zone 列表，请稍候..."
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?per_page=50" \
        -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_TOKEN" -H "Content-Type: application/json")
    # 检查 API 调用是否成功
    if echo "$response" | grep -q '"success":false'; then
        echo -e "${red}❌ API 验证失败！请检查 Token 和邮箱是否正确${reset}"
        continue  # 重新输入凭证
    fi
    # 解析 Zone 列表
    zone_count=$(echo "$response" | grep -c '"id":"')
    if [ "$zone_count" -eq 0 ]; then
        error_exit "未获取到任何域名，请确认账户下已添加域名"
    fi

    # 使用 Python 解析 JSON（若可用）
    zone_index=1
    declare -a ZONE_IDS ZONE_NAMES ACCOUNT_IDS
    if command -v python3 &>/dev/null || command -v python &>/dev/null; then
        zones_output=$(
        { command -v python3 &>/dev/null && python3; } <<EOF
import sys, json
data = json.load(sys.stdin)
for z in data.get("result", []):
    zid = z.get("id"); zname = z.get("name"); accid = z.get("account", {}).get("id")
    if zid and zname:
        print(f"{zid} {zname} {accid if accid else ''}")
EOF
        ) <<< "$response"
        # 将解析结果存入数组并打印列表
        IFS=$'\n'
        for line in $zones_output; do
            ZONE_IDS[$zone_index]=$(echo "$line" | awk '{print $1}')
            ZONE_NAMES[$zone_index]=$(echo "$line" | awk '{print $2}')
            ACCOUNT_IDS[$zone_index]=$(echo "$line" | awk '{print $3}')
            echo -e "${yellow}$zone_index${reset}. ${green}${ZONE_NAMES[$zone_index]}${reset}"
            ((zone_index++))
        done
        unset IFS
    else
        # 无 Python，则使用 grep/sed 简单解析
        response_no_space=$(echo "$response" | tr -d '\n ')
        zones_data=$(echo "$response_no_space" | sed -e 's/.*"result":\[//' -e 's/\].*//')
        IFS='}' read -ra ZONES <<< "$zones_data"
        for zone in "${ZONES[@]}"; do
            [[ "$zone" == "" || "$zone" == "[" ]] && continue
            zid=$(echo "$zone" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
            zname=$(echo "$zone" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')
            accid=$(echo "$zone" | sed -n 's/.*"account":{[^}]*"id":"\([^"]*\)".*/\1/p')
            if [ -n "$zid" ] && [ -n "$zname" ]; then
                ZONE_IDS[$zone_index]="$zid"
                ZONE_NAMES[$zone_index]="$zname"
                ACCOUNT_IDS[$zone_index]="$accid"
                echo -e "${yellow}$zone_index${reset}. ${green}$zname${reset}"
                ((zone_index++))
            fi
        done
        unset IFS
    fi

    # 提示选择 Zone
    echo ""
    read -p "$(echo -e "${cyan}请选择要使用的主域名 (输入序号): ${reset}")" zone_choice
    [[ "$zone_choice" =~ ^[Qq](uit)?$ ]] && confirm_exit && continue
    if ! [[ "$zone_choice" =~ ^[0-9]+$ ]] || [ "$zone_choice" -lt 1 ] || [ "$zone_choice" -ge "$zone_index" ]; then
        echo -e "${red}❌ 无效选择，请输入以上列表中的编号${reset}"
        continue
    fi

    CF_ZONE_ID="${ZONE_IDS[$zone_choice]}"
    CF_MAIN_DOMAIN="${ZONE_NAMES[$zone_choice]}"
    CF_ACCOUNT_ID="${ACCOUNT_IDS[$zone_choice]}"

    if [ -z "$CF_ZONE_ID" ] || [ -z "$CF_MAIN_DOMAIN" ]; then
        echo -e "${red}❌ 选择无效，请重试${reset}"
        continue
    fi

    echo -e "${green}✔️  已选择域名：${lightpink}$CF_MAIN_DOMAIN${reset} (Zone ID: ${lightpink}$CF_ZONE_ID${reset})"
    break
done

# ===== Cloudflare 隧道创建 =====
echo -e "\n${yellow}📑 请输入要创建的隧道名称（仅字母、数字和短横线）${reset}"
while true; do
    read -p "$(echo -e "${cyan}隧道名称: ${reset}")" TUNNEL_NAME
    [[ "$TUNNEL_NAME" =~ ^[Qq](uit)?$ ]] && confirm_exit && continue
    if [[ -z "$TUNNEL_NAME" ]]; then
        echo -e "${red}❌ 隧道名称不能为空${reset}"
        continue
    elif [[ ! "$TUNNEL_NAME" =~ ^[0-9A-Za-z_-]+$ ]]; then
        echo -e "${red}❌ 隧道名称仅允许字母、数字和下划线/中划线${reset}"
        continue
    fi
    echo -e "${green}✔️  隧道名称：${lightpink}$TUNNEL_NAME${reset}"
    break
done

# 如果未登录 Cloudflare Zero Trust，需要登录获取证书
if [ ! -f "$HOME/.cloudflared/cert.pem" ]; then
    warning "首次使用需要 Cloudflare 授权登录..."
    info "🌐 正在启动浏览器进行登录授权，请完成网页上的操作"
    cloudflared tunnel login || error_exit "Cloudflare 登录授权失败，请重试"
    success "Cloudflare 授权登录成功"
fi

# 创建隧道
info "🔧 正在创建隧道，请稍候..."
create_output=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1)
create_exit_code=$?
if [ $create_exit_code -ne 0 ]; then
    # 检查是否因为同名隧道已存在
    if echo "$create_output" | grep -q -i "already exists"; then
        warning "隧道 ${TUNNEL_NAME} 已存在。"
        # 提示删除已有的同名隧道
        read -p "$(echo -e "${yellow}是否删除已存在的隧道 \"$TUNNEL_NAME\" 并重新创建？(y/n): ${reset}")" -n 1 del_choice
        echo ""
        if [[ $del_choice =~ ^[yY]$ ]]; then
            info "🗑️ 删除旧隧道 ${TUNNEL_NAME}..."
            cloudflared tunnel delete -f "$TUNNEL_NAME" && success "旧隧道已删除" || error_exit "旧隧道删除失败，请手动检查"
            # 删除旧的本地凭证文件
            old_cred_file=$(find "$CONFIG_DIR" -maxdepth 1 -name "*.json" -type f -printf "%f\n" | grep -m1 -F "$TUNNEL_NAME")
            if [ -n "$old_cred_file" ] && [ -f "$CONFIG_DIR/$old_cred_file" ]; then
                rm -f "$CONFIG_DIR/$old_cred_file"
            fi
            # 重试创建隧道
            create_output=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1) 
            create_exit_code=$?
        else
            error_exit "已存在同名隧道，操作中止"
        fi
    fi
fi
if [ $create_exit_code -ne 0 ]; then
    echo -e "${red}❌ 隧道创建失败，错误信息:${reset}\n$create_output"
    error_exit "请修正错误后重试"
fi

# 提取新隧道ID
TUNNEL_ID=$(echo "$create_output" | grep -ioE "[0-9a-f-]{36}")
if [ -z "$TUNNEL_ID" ]; then
    # 未能从输出提取ID，尝试使用 Cloudflare API 获取
    TUNNEL_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/cfd_tunnel?name=$TUNNEL_NAME" \
        -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_TOKEN" | grep -ioE "[0-9a-f-]{36}" | head -n1)
fi
if [ -z "$TUNNEL_ID" ]; then
    error_exit "隧道创建成功，但无法获取隧道 ID"
fi
echo -e "${green}✔️  隧道已创建：${lightpink}$TUNNEL_NAME${reset} (ID: ${lightpink}$TUNNEL_ID${reset})"

# 生成配置文件 config.yml
cat > "$CONFIG_FILE" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CONFIG_DIR/$TUNNEL_ID.json
EOF

# 清理旧配置和凭证文件（如果有）
if [ -n "$old_tunnel_id" ] && [ "$old_tunnel_id" != "$TUNNEL_ID" ]; then
    if [ -f "$CONFIG_DIR/$old_tunnel_id.json" ]; then
        rm -f "$CONFIG_DIR/$old_tunnel_id.json"
    fi
fi

success "配置文件已生成: ${lightpink}$CONFIG_FILE${reset}"

# ===== DNS 记录添加 =====
echo -e "\n${yellow}📡 正在获取本机公网 IP...${reset}"
# 多来源获取 IPv4/IPv6
IPV4=""
IPV6=""
ipv4_sources=( "ifconfig.co" "api.ipify.org" "ipinfo.io/ip" )
ipv6_sources=( "ifconfig.co" "api64.ipify.org" )
for src in "${ipv4_sources[@]}"; do
    resp=$(curl -s4 --max-time 5 "$src")
    if [[ -n "$resp" && "$resp" != "获取失败" ]]; then
        if [[ "$resp" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            IPV4="$resp"
            break
        fi
    fi
done
for src in "${ipv6_sources[@]}"; do
    resp=$(curl -s6 --max-time 5 "$src")
    if [[ -n "$resp" && "$resp" != "获取失败" ]]; then
        # 简单验证 IPv6 格式（包含冒号）
        if [[ "$resp" =~ : ]]; then
            IPV6="$resp"
            break
        fi
    fi
done
[ -z "$IPV4" ] && IPV4="获取失败"
[ -z "$IPV6" ] && IPV6="获取失败"
echo -e "${yellow}📶 当前公网 IPv4：${lightpink}$IPV4${reset}"
echo -e "${yellow}📶 当前公网 IPv6：${lightpink}$IPV6${reset}"

echo -e "\n${orange}开始添加 DNS 解析记录（A/AAAA/CNAME）${reset}"
success_count=0
fail_count=0
success_list=()
fail_list=()

add_more="y"
while [[ $add_more =~ ^[yY]$ ]]; do
    # 选择记录类型
    record_type=""
    while true; do
        read -p "$(echo -e "${cyan}请选择记录类型（A/AAAA/CNAME）: ${reset}")" record_type
        [[ "$record_type" =~ ^[Qq](uit)?$ ]] && confirm_exit && continue
        record_type=${record_type^^}  # 转大写
        if [[ "$record_type" != "A" && "$record_type" != "AAAA" && "$record_type" != "CNAME" ]]; then
            echo -e "${red}❌ 记录类型无效，请输入 A、AAAA 或 CNAME${reset}"
            continue
        fi
        break
    done

    # 记录名称
    record_name=""
    while true; do
        read -p "$(echo -e "${cyan}请输入主机记录名称（如 www，根域请直接回车）: ${reset}")" record_name
        [[ "$record_name" =~ ^[Qq](uit)?$ ]] && confirm_exit && continue
        # 空则表示根域
        if [[ -z "$record_name" ]]; then
            record_name="$CF_MAIN_DOMAIN"
            echo -e "${green}✔️  主机记录：${lightpink}<根域>${reset}"
        else
            # 验证子域名格式
            if ! validate_domain "$record_name"; then
                echo -e "${red}❌ 主机记录格式无效，请勿包含协议或顶级域${reset}"
                continue
            fi
            # 如果用户输入类似 "www.example.com"，去掉后缀得到主机名
            record_name=${record_name%.${CF_MAIN_DOMAIN}}
            record_name=${record_name#.}  # 去掉可能的起始点
            full_name="$record_name.$CF_MAIN_DOMAIN"
            echo -e "${green}✔️  主机记录：${lightpink}$([ "$full_name" = "$CF_MAIN_DOMAIN" ] && echo "<根域>" || echo "$full_name")${reset}"
            record_name="$full_name"
        fi
        break
    done

    # 准备记录内容
    record_content=""
    if [[ "$record_type" == "A" || "$record_type" == "AAAA" ]]; then
        if [[ "$record_type" == "A" ]]; then
            if [[ "$IPV4" != "获取失败" ]]; then
                # 提示使用检测到的 IPv4
                read -p "$(echo -e "${yellow}检测到 IPv4: $IPV4，是否使用该 IP？(y/n): ${reset}")" -n 1 use_ip
                echo ""
                if [[ $use_ip =~ ^[yY]$ ]]; then
                    record_content="$IPV4"
                fi
            fi
            if [[ -z "$record_content" ]]; then
                # 手动输入 IPv4
                while true; do
                    read -p "$(echo -e "${cyan}请输入 IPv4 地址: ${reset}")" record_content
                    [[ "$record_content" =~ ^[Qq](uit)?$ ]] && confirm_exit && continue
                    if [[ ! "$record_content" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
                        echo -e "${red}❌ IPv4 地址格式不正确${reset}"
                        continue
                    fi
                    break
                done
            fi
        else  # AAAA
            if [[ "$IPV6" != "获取失败" ]]; then
                read -p "$(echo -e "${yellow}检测到 IPv6: $IPV6，是否使用该 IP？(y/n): ${reset}")" -n 1 use_ip
                echo ""
                if [[ $use_ip =~ ^[yY]$ ]]; then
                    record_content="$IPV6"
                fi
            fi
            if [[ -z "$record_content" ]]; then
                while true; do
                    read -p "$(echo -e "${cyan}请输入 IPv6 地址: ${reset}")" record_content
                    [[ "$record_content" =~ ^[Qq](uit)?$ ]] && confirm_exit && continue
                    if [[ ! "$record_content" =~ : ]]; then
                        echo -e "${red}❌ IPv6 地址格式不正确${reset}"
                        continue
                    fi
                    break
                done
            fi
        fi
        echo -e "${green}✔️  记录内容：${lightpink}$record_content${reset}"
    else
        # CNAME 记录内容默认为隧道域名 <TunnelID>.cfargotunnel.com
        record_content="$TUNNEL_ID.cfargotunnel.com"
        echo -e "${green}✔️  记录内容：${lightpink}$record_content${reset}"
    fi

    # 添加 DNS 记录（优先使用 API）
    echo -e "${blue}🔹 正在添加 ${record_type} 记录：${record_name} -> ${record_content}${reset}"
    api_response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_TOKEN" -H "Content-Type: application/json" \
        --data '{"type":"'"$record_type"'","name":"'"$record_name"'","content":"'"$record_content"'","ttl":3600,"proxied":true}')
    if echo "$api_response" | grep -q '"success":true'; then
        echo -e "${green}✔️  DNS 记录 ${record_name} (${record_type}) 添加成功${reset}"
        success_list+=("${record_name} (${record_type})")
        success_count=$((success_count+1))
    else
        echo -e "${red}❌ API 添加失败${reset}"
        # 输出错误信息（如果有）
        err_msg=$(echo "$api_response" | grep -o '"message":"[^"]*"' | cut -d':' -f2- | head -n1)
        if [ -n "$err_msg" ]; then
            echo -e "${red}错误信息: ${err_msg}${reset}"
        fi
        # 尝试使用 cloudflared CLI fallback（仅限 CNAME 隧道路由）
        if [[ "$record_type" == "CNAME" ]]; then
            info "尝试使用 cloudflared CLI 添加 DNS 记录..."
            if cloudflared tunnel route dns "$TUNNEL_NAME" "$record_name" &>/dev/null; then
                echo -e "${green}✔️  DNS 记录 ${record_name} (${record_type}) 添加成功 (通过CLI)${reset}"
                success_list+=("${record_name} (${record_type})")
                success_count=$((success_count+1))
            else
                echo -e "${red}❌ cloudflared CLI 添加记录失败${reset}"
                fail_list+=("${record_name} (${record_type})")
                fail_count=$((fail_count+1))
            fi
        else
            fail_list+=("${record_name} (${record_type})")
            fail_count=$((fail_count+1))
        fi
    fi

    # 是否继续添加下一条
    echo ""
    read -p "$(echo -e "${yellow}是否继续添加其它记录？(y/n): ${reset}")" -n 1 add_more
    echo ""
    [[ "$add_more" =~ ^[Qq](uit)?$ ]] && confirm_exit && add_more="y"
done

# ===== 结果汇总 =====
echo ""
if [ $success_count -gt 0 ]; then
    echo -e "${green}✅ 成功添加记录数: $success_count${reset}"
    for rec in "${success_list[@]}"; do
        echo -e "   - ${lightpink}$rec${reset}"
    done
else
    echo -e "${red}⚠️  没有成功添加的记录${reset}"
fi
if [ $fail_count -gt 0 ]; then
    echo -e "${red}❌ 未添加记录数: $fail_count${reset}"
    for rec in "${fail_list[@]}"; do
        echo -e "   - ${lightpink}$rec${reset}"
    done
else
    echo -e "${green}✔️  没有失败的记录${reset}"
fi

# 生成信息文件
INFO_FILE="$CONFIG_DIR/tunnel_info.txt"
echo -e "Cloudflare 隧道配置信息 - $(date +"%Y-%m-%d %H:%M:%S")" > "$INFO_FILE"
echo "======================================" >> "$INFO_FILE"
echo "Cloudflare Email: $CF_EMAIL" >> "$INFO_FILE"
echo "Cloudflare API Key: $CF_TOKEN" >> "$INFO_FILE"
echo "Zone: $CF_MAIN_DOMAIN (Zone ID: $CF_ZONE_ID)" >> "$INFO_FILE"
echo "隧道名称: $TUNNEL_NAME" >> "$INFO_FILE"
echo "隧道 ID: $TUNNEL_ID" >> "$INFO_FILE"
echo "配置文件: $CONFIG_FILE" >> "$INFO_FILE"
echo "凭证文件: $CONFIG_DIR/$TUNNEL_ID.json" >> "$INFO_FILE"
echo "成功添加记录 ($success_count):" >> "$INFO_FILE"
if [ $success_count -gt 0 ]; then
    for rec in "${success_list[@]}"; do echo " - $rec" >> "$INFO_FILE"; done
else
    echo " 无" >> "$INFO_FILE"
fi
echo "失败添加记录 ($fail_count):" >> "$INFO_FILE"
if [ $fail_count -gt 0 ]; then
    for rec in "${fail_list[@]}"; do echo " - $rec" >> "$INFO_FILE"; done
else
    echo " 无" >> "$INFO_FILE"
fi

# 完成提示
echo -e "\n${green}✅ 所有操作已完成！${reset}"
echo -e "${cyan}╔══════════════════════════════════════════════════════════════╗${reset}"
echo -e "${cyan}║${reset}          ${green}🎉 Cloudflare 隧道及 DNS 配置完成！${reset}          ${cyan}║${reset}"
echo -e "${cyan}╚══════════════════════════════════════════════════════════════╝${reset}"
echo -e "${yellow}📄 隧道信息已保存到: ${reset}${lightpink}$INFO_FILE${reset}"
echo -e "${yellow}👉 请使用以下命令启动隧道: ${reset}${lightpink}cloudflared tunnel run $TUNNEL_NAME${reset}\n"
