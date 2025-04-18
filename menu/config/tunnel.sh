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
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "${cyan}                            ${orange}☁️ Cloudflare 隧道 & DNS 自动配置${reset}   "                            
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
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
  /root/VPN/cloudflared tunnel login || error_exit "Cloudflare 登录授权失败，请检查网络后重试"
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
CREATE_OUTPUT=$(/root/VPN/cloudflared tunnel create "$TUNNEL_NAME" 2>&1)
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

footer
