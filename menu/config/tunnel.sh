#!/bin/bash

# 颜色定义
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
purple="\033[1;35m"
cyan="\033[1;36m"
orange="\033[38;5;214m"
pink="\033[1;35m"
lightpink="\033[38;5;213m"
reset="\033[0m"

# 辅助函数定义
function header() {
  echo -e "${cyan}╔═══════════════════════════════════════════════════════════════╗${reset}"
  echo -e "${cyan}                              ☁️ Cloudflare 隧道 & DNS 自动配置                               ${reset}"
  echo -e "${cyan}╠═══════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
  echo -e "${cyan}╚═══════════════════════════════════════════════════════════════╝${reset}"
}

function info() {
  echo -e "${cyan}🔹 $1${reset}"
}

function success() {
  echo -e "${green}✅ $1${reset}"
}

function warning() {
  echo -e "${yellow}⚠️  $1${reset}"
}

function error_exit() {
  echo -e "${red}❌ $1${reset}"
  exit 1
}

function validate_domain() {
  [[ "$1" =~ ^([A-Za-z0-9]([A-Za-z0-9\-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]]
}

function validate_token() {
  [[ "$1" =~ ^[A-Za-z0-9\_\-]{30,100}$ ]]
}

# 初始化配置路径
CONFIG_PATH="/root/VPN/config/cloudflared.yaml"
INFO_PATH="/root/VPN/cloudflared_tunnel_info.txt"
mkdir -p /root/VPN/config

# 开始脚本执行
clear
header

# 输入 Cloudflare API Token
while true; do
  read -p "$(echo -e "\n${cyan}请输入 Cloudflare API 令牌 (API Token): ${reset}")" TOKEN
  if [ -z "$TOKEN" ]; then
    echo -e "${red}❌ API 令牌不能为空，请重新输入${reset}"
  elif validate_token "$TOKEN"; then
    echo -e "${green}✔️  API 令牌已输入${reset}"
    break
  else
    echo -e "${red}❌ API 令牌格式无效，请重新输入${reset}"
  fi
done

# 输入主域名并获取 Zone ID
while true; do
  read -p "$(echo -e "\n${cyan}请输入顶级域名（如：example.com）: ${reset}")" DOMAIN
  if [ -z "$DOMAIN" ]; then
    echo -e "${red}❌ 域名不能为空，请重新输入${reset}"
  elif validate_domain "$DOMAIN"; then
    echo -e "${green}✔️  域名：${lightpink}$DOMAIN${reset}"
    break
  else
    echo -e "${red}❌ 域名格式无效，请重新输入（示例：example.com）${reset}"
  fi
done

info "🔍 获取域名 ${DOMAIN} 的 Zone ID..."
zone_resp=$(curl -s -X GET -H "Authorization: Bearer $TOKEN" "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN&status=active")
if echo "$zone_resp" | grep -q '"success":false'; then
  error_exit "无法获取域名 ${DOMAIN} 的 Zone ID，请检查 API 令牌权限"
fi
ZONE_ID=$(echo "$zone_resp" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
if [ -z "$ZONE_ID" ]; then
  error_exit "找不到域名 ${DOMAIN} ，请确认该域名已接入 Cloudflare"
fi
success "已获取 Zone ID: ${ZONE_ID}"

# Cloudflared 登录认证
if [ ! -f "$HOME/.cloudflared/cert.pem" ]; then
  info "🌐 正在进行 Cloudflare 授权登录，请按提示完成浏览器验证..."
  cloudflared tunnel login || error_exit "Cloudflare 登录授权失败，请检查网络后重试"
fi
success "Cloudflare 账号授权登录完成"

# 输入并创建 Cloudflare 隧道
while true; do
  read -p "$(echo -e "\n${cyan}请输入隧道名称: ${reset}")" TUNNEL_NAME
  if [ -z "$TUNNEL_NAME" ]; then
    echo -e "${red}❌ 隧道名称不能为空，请重新输入${reset}"
  else
    echo -e "${green}✔️  隧道名称：${lightpink}$TUNNEL_NAME${reset}"
    break
  fi
done

info "🚀 正在创建隧道，请稍候..."
CREATE_OUTPUT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1)
if [ $? -ne 0 ]; then
  if echo "$CREATE_OUTPUT" | grep -q "already exists"; then
    error_exit "隧道名称 ${TUNNEL_NAME} 已存在，请更换名称后重试"
  else
    error_exit "隧道创建失败：$(echo "$CREATE_OUTPUT" | tail -1)"
  fi
fi
TUNNEL_ID=$(echo "$CREATE_OUTPUT" | grep -F "Created tunnel" | awk '{print $NF}')
CRED_FILE=$(echo "$CREATE_OUTPUT" | grep -o "/[^ ]*\\.json")
[ -z "$TUNNEL_ID" ] && error_exit "无法解析隧道 ID，请检查 cloudflared 输出"
[ -z "$CRED_FILE" ] && CRED_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"
success "隧道创建成功 (ID: ${TUNNEL_ID})"

# 生成 Cloudflared 配置文件
cat > "$CONFIG_PATH" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $CRED_FILE
EOF
chmod 777 "$CONFIG_PATH"
echo -e "${green}✅ 隧道配置已生成: ${lightpink}$CONFIG_PATH${reset}"
echo -e "${green}🔓 已开放完整权限${reset}"

# 获取公网 IPv4 / IPv6 地址
echo -e "\n${yellow}📡 正在获取公网 IP 地址...${reset}"
IPV4=$(curl -s4 ifconfig.co || curl -s4 ip.sb || echo "")
IPV6=$(curl -s6 ifconfig.co || curl -s6 ip.sb || echo "")
[ -z "$IPV4" ] && IPV4="获取失败"
[ -z "$IPV6" ] && IPV6="获取失败"
echo -e "${yellow}📶 当前公网 IPv4：${lightpink}$IPV4${reset}"
echo -e "${yellow}📶 当前公网 IPv6：${lightpink}$IPV6${reset}"

# DNS 记录添加
success_count=0
fail_count=0

# 添加 A 记录
while true; do
  read -p "$(echo -e "\n${yellow}是否添加 IPv4 A 记录？(y/n): ${reset}")" -n 1 add_a
  echo ""
  case "$add_a" in
    [yY])
      if [ "$IPV4" = "获取失败" ]; then
        warning "无法获取有效的 IPv4 地址，跳过 A 记录添加"
        break
      fi
      while true; do
        read -p "$(echo -e "${cyan}请输入 A 记录主机名（不含域名，@ 表示根域）: ${reset}")" A_NAME
        if [ -z "$A_NAME" ] || [ "$A_NAME" = "@" ]; then
          RECORD_NAME="$DOMAIN"
        else
          if [[ "$A_NAME" =~ \  ]]; then
            echo -e "${red}❌ 名称格式无效，请勿包含空格${reset}"
            continue
          fi
          RECORD_NAME="${A_NAME}.${DOMAIN}"
        fi
        break
      done
      info "✨ 正在添加 A 记录: ${RECORD_NAME} -> $IPV4"
      dns_get=$(curl -s -X GET -H "Authorization: Bearer $TOKEN" "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$RECORD_NAME&type=A")
      if echo "$dns_get" | grep -q '"id":"'; then
        rec_id=$(echo "$dns_get" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
        old_ip=$(echo "$dns_get" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p')
        if [ "$old_ip" = "$IPV4" ]; then
          success "A 记录已存在，无需修改: ${RECORD_NAME} -> $IPV4"
          ((success_count++))
        else
          update_resp=$(curl -s -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
            --data '{"type":"A","name":"'"$RECORD_NAME"'","content":"'"$IPV4"'","ttl":1,"proxied":true}' \
            "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$rec_id")
          if echo "$update_resp" | grep -q '"success":true'; then
            success "A 记录已更新: ${RECORD_NAME} -> $IPV4"
            ((success_count++))
          else
            err_msg=$(echo "$update_resp" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')
            echo -e "${red}❌ A 记录更新失败: ${err_msg:-更新请求发生错误}${reset}"
            ((fail_count++))
          fi
        fi
      else
        create_resp=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
          --data '{"type":"A","name":"'"$RECORD_NAME"'","content":"'"$IPV4"'","ttl":1,"proxied":true}' \
          "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records")
        if echo "$create_resp" | grep -q '"success":true'; then
          success "A 记录添加成功: ${RECORD_NAME} -> $IPV4"
          ((success_count++))
        else
          err_msg=$(echo "$create_resp" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')
          echo -e "${red}❌ A 记录添加失败: ${err_msg:-添加请求发生错误}${reset}"
          ((fail_count++))
        fi
      fi
      break
      ;;
    [nN]) break ;;
    *) echo -e "${red}❌ 无效输入，请输入 y 或 n${reset}" ;;
  esac
done

# 添加 AAAA 记录
while true; do
  read -p "$(echo -e "\n${yellow}是否添加 IPv6 AAAA 记录？(y/n): ${reset}")" -n 1 add_aaaa
  echo ""
  case "$add_aaaa" in
    [yY])
      if [ "$IPV6" = "获取失败" ]; then
        warning "无法获取有效的 IPv6 地址，跳过 AAAA 记录添加"
        break
      fi
      while true; do
        read -p "$(echo -e "${cyan}请输入 AAAA 记录主机名（不含域名，@ 表示根域）: ${reset}")" AAAA_NAME
        if [ -z "$AAAA_NAME" ] || [ "$AAAA_NAME" = "@" ]; then
          RECORD_NAME="$DOMAIN"
        else
          if [[ "$AAAA_NAME" =~ \  ]]; then
            echo -e "${red}❌ 名称格式无效，请勿包含空格${reset}"
            continue
          fi
          RECORD_NAME="${AAAA_NAME}.${DOMAIN}"
        fi
        break
      done
      info "✨ 正在添加 AAAA 记录: ${RECORD_NAME} -> $IPV6"
      dns_get=$(curl -s -X GET -H "Authorization: Bearer $TOKEN" "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$RECORD_NAME&type=AAAA")
      if echo "$dns_get" | grep -q '"id":"'; then
        rec_id=$(echo "$dns_get" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
        old_ip=$(echo "$dns_get" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p')
        if [ "$old_ip" = "$IPV6" ]; then
          success "AAAA 记录已存在，无需修改: ${RECORD_NAME} -> $IPV6"
          ((success_count++))
        else
          update_resp=$(curl -s -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
            --data '{"type":"AAAA","name":"'"$RECORD_NAME"'","content":"'"$IPV6"'","ttl":1,"proxied":true}' \
            "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$rec_id")
          if echo "$update_resp" | grep -q '"success":true'; then
            success "AAAA 记录已更新: ${RECORD_NAME} -> $IPV6"
            ((success_count++))
          else
            err_msg=$(echo "$update_resp" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')
            echo -e "${red}❌ AAAA 记录更新失败: ${err_msg:-更新请求发生错误}${reset}"
            ((fail_count++))
          fi
        fi
      else
        create_resp=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
          --data '{"type":"AAAA","name":"'"$RECORD_NAME"'","content":"'"$IPV6"'","ttl":1,"proxied":true}' \
          "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records")
        if echo "$create_resp" | grep -q '"success":true'; then
          success "AAAA 记录添加成功: ${RECORD_NAME} -> $IPV6"
          ((success_count++))
        else
          err_msg=$(echo "$create_resp" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')
          echo -e "${red}❌ AAAA 记录添加失败: ${err_msg:-添加请求发生错误}${reset}"
          ((fail_count++))
        fi
      fi
      break
      ;;
    [nN]) break ;;
    *) echo -e "${red}❌ 无效输入，请输入 y 或 n${reset}" ;;
  esac
done

# 添加 CNAME 记录
while true; do
  read -p "$(echo -e "\n${yellow}是否添加 Cloudflare 隧道 CNAME 记录？(y/n): ${reset}")" -n 1 add_cname
  echo ""
  case "$add_cname" in
    [yY])
      while true; do
        read -p "$(echo -e "${cyan}请输入 CNAME 记录主机名（不含域名）: ${reset}")" CNAME_NAME
        if [ -z "$CNAME_NAME" ]; then
          echo -e "${red}❌ 记录名称不能为空，请重新输入${reset}"
        elif [[ "$CNAME_NAME" =~ \  ]]; then
          echo -e "${red}❌ 名称格式无效，请勿包含空格${reset}"
        else
          RECORD_NAME="${CNAME_NAME}.${DOMAIN}"
          echo -e "${green}✔️  CNAME 域名：${lightpink}$RECORD_NAME${reset}"
          break
        fi
      done
      TARGET="${TUNNEL_ID}.cfargotunnel.com"
      info "✨ 正在添加 CNAME 记录: ${RECORD_NAME} -> $TARGET"
      cname_get=$(curl -s -X GET -H "Authorization: Bearer $TOKEN" "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$RECORD_NAME")
      if echo "$cname_get" | grep -q '"id":"'; then
        rec_type=$(echo "$cname_get" | sed -n 's/.*"type":"\([^"]*\)".*/\1/p')
        rec_id=$(echo "$cname_get" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
        if [ "$rec_type" = "CNAME" ]; then
          old_target=$(echo "$cname_get" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p')
          if [ "$old_target" = "$TARGET" ]; then
            success "CNAME 记录已存在，无需修改: ${RECORD_NAME} -> $TARGET"
            ((success_count++))
          else
            update_resp=$(curl -s -X PUT -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
              --data '{"type":"CNAME","name":"'"$RECORD_NAME"'","content":"'"$TARGET"'","ttl":1,"proxied":true}' \
              "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$rec_id")
            if echo "$update_resp" | grep -q '"success":true'; then
              success "CNAME 记录已更新: ${RECORD_NAME} -> $TARGET"
              ((success_count++))
            else
              warning "CNAME 记录更新失败，尝试使用 Cloudflared CLI..."
              if cloudflared tunnel route dns "$TUNNEL_NAME" "$RECORD_NAME" 2>/dev/null; then
                success "CNAME 记录更新成功 (通过 cloudflared CLI): ${RECORD_NAME}"
                ((success_count++))
              else
                echo -e "${red}❌ CNAME 记录更新失败${reset}"
                ((fail_count++))
              fi
            fi
          fi
        else
          echo -e "${red}❌ 已存在同名 ${rec_type} 记录 (${RECORD_NAME}), 无法添加 CNAME${reset}"
          ((fail_count++))
        fi
      else
        create_resp=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
          --data '{"type":"CNAME","name":"'"$RECORD_NAME"'","content":"'"$TARGET"'","ttl":1,"proxied":true}' \
          "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records")
        if echo "$create_resp" | grep -q '"success":true'; then
          success "CNAME 记录添加成功: ${RECORD_NAME} -> $TARGET"
          ((success_count++))
        else
          warning "CNAME 记录添加失败，尝试使用 Cloudflared CLI..."
          if cloudflared tunnel route dns "$TUNNEL_NAME" "$RECORD_NAME" 2>/dev/null; then
            success "CNAME 记录添加成功 (通过 cloudflared CLI): ${RECORD_NAME}"
            ((success_count++))
          else
            err_msg=$(echo "$create_resp" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')
            echo -e "${red}❌ CNAME 记录添加失败: ${err_msg:-添加请求发生错误}${reset}"
            ((fail_count++))
          fi
        fi
      fi
      break
      ;;
    [nN]) break ;;
    *) echo -e "${red}❌ 无效输入，请输入 y 或 n${reset}" ;;
  esac
done

# 配置完成摘要输出
echo -e "\n${cyan}╠═══════════════════════════════════════════════════════════════╣${reset}"
echo -e "${cyan}                              🌐 配置完成摘要                               ${reset}"
echo -e "${cyan}╠═══════════════════════════════════════════════════════════════╣${reset}"
echo -e " ${lightpink}域名：         ${reset}${green}$DOMAIN${reset}"
echo -e " ${lightpink}隧道名称：     ${reset}${green}$TUNNEL_NAME${reset}"
echo -e " ${lightpink}隧道 ID：      ${reset}${green}$TUNNEL_ID${reset}"
echo -e " ${lightpink}证书文件：     ${reset}${green}$CRED_FILE${reset}"
echo -e " ${lightpink}配置文件：     ${reset}${green}$CONFIG_PATH${reset}"
echo -e " ${lightpink}成功记录数：   ${reset}${green}$success_count 条${reset}"
echo -e " ${lightpink}失败记录数：   ${reset}${green}$fail_count 条${reset}"
echo -e "${green}✅ 配置详情已保存至: ${lightpink}$INFO_PATH${reset}"

# 保存配置信息文件
cat > "$INFO_PATH" <<EOF
域名: $DOMAIN
隧道名称: $TUNNEL_NAME
隧道ID: $TUNNEL_ID
证书文件: $CRED_FILE
配置文件: $CONFIG_PATH
成功记录: $success_count 条
失败记录: $fail_count 条
EOF
chmod 777 "$INFO_PATH"

footer
