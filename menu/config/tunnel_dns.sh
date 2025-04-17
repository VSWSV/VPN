#!/bin/bash

# 颜色定义
cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
lightpink="\033[38;5;213m"
reset="\033[0m"

CONFIG_DIR="/root/VPN/config"
mkdir -p $CONFIG_DIR
CLOUDFLARE_BIN="/root/VPN/cloudflared"

# 🧠 请先手动填写以下变量
API_TOKEN="填写你的 Cloudflare API Token"
ZONE_NAME="vswsv.com"                 # 主域名
TUNNEL_SUB="vpn"                      # 子域名前缀（如 vpn）
EMAIL="填写你的账号邮箱"               # 如果用 Global Key，则可能需要邮箱

header() {
echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "${cyan}                  ☁️ Cloudflare 隧道 + 自动添加 DNS 记录（A/AAAA/CNAME）              ${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

footer() {
echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

get_zone_id() {
  curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" | jq -r '.result[0].id'
}

add_dns_record() {
  local TYPE=$1
  local NAME=$2
  local VALUE=$3

  curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    --data '{
      "type":"'"$TYPE"'",
      "name":"'"$NAME"'",
      "content":"'"$VALUE"'",
      "ttl":120,
      "proxied":false
    }' | jq -r '.success'
}

clear
header

# 检查 cloudflared
if [ ! -f "$CLOUDFLARE_BIN" ]; then
  echo -e "${red}❌ 未找到 cloudflared，请先安装！${reset}"
  footer; exit 1
fi

echo -e "${yellow}📤 执行 Cloudflare 授权登录...${reset}"
$CLOUDFLARE_BIN tunnel login

read -p "$(echo -e "${cyan}请输入隧道名称（建议英文）: ${reset}")" TUNNEL_NAME
read -p "$(echo -e "${cyan}请输入完整 SNI 域名（如 vpn.vswsv.com）: ${reset}")" FULL_DOMAIN

TUNNEL_HOST=$FULL_DOMAIN
SUB_DOMAIN=${TUNNEL_HOST%%.$ZONE_NAME}

$CLOUDFLARE_BIN tunnel create "$TUNNEL_NAME"
TUNNEL_ID=$($CLOUDFLARE_BIN tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')

cat > "/root/.cloudflared/config.yml" <<EOF
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json

ingress:
  - hostname: $TUNNEL_HOST
    service: http://localhost:80
  - service: http_status:404
EOF

$CLOUDFLARE_BIN tunnel route dns "$TUNNEL_NAME" "$TUNNEL_HOST"

echo -e "${green}✅ CNAME 记录已设置，开始添加 A/AAAA ...${reset}"

# 获取 zone_id
ZONE_ID=$(get_zone_id)
[ -z "$ZONE_ID" ] && echo -e "${red}❌ 无法获取 Zone ID，检查 API Token 是否正确${reset}" && footer && exit 1

IPV4=$(curl -s4 ifconfig.co || echo "192.0.2.1")
IPV6=$(curl -s6 ifconfig.co || echo "100::")

add_dns_record "A" "$TUNNEL_HOST" "$IPV4"
add_dns_record "AAAA" "$TUNNEL_HOST" "$IPV6"

echo -e "${green}🎉 所有记录设置完成！${reset}"
footer
