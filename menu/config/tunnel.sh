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

header() {
echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "${cyan}                  ☁️ Cloudflare 隧道 + 自动添加 DNS 记录（A/AAAA/CNAME）              ${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

footer() {
echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

validate_domain() {
  [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

clear
header

# 检查 cloudflared
if [ ! -f "$CLOUDFLARE_BIN" ]; then
  echo -e "${red}❌ 未找到 cloudflared，请先安装！${reset}"
  footer; exit 1
fi

# 第一步：输入域名信息
while true; do
  read -p "$(echo -e "\n${cyan}请输入主域名（如 vswsv.com）: ${reset}")" ZONE_NAME
  if validate_domain "$ZONE_NAME"; then
    break
  else
    echo -e "${red}❌ 域名格式无效，请重新输入${reset}"
  fi
done

while true; do
  read -p "$(echo -e "${cyan}请输入子域名前缀（如 vpn）: ${reset}")" TUNNEL_SUB
  if [ -n "$TUNNEL_SUB" ]; then
    break
  else
    echo -e "${red}❌ 子域名不能为空，请重新输入${reset}"
  fi
done

FULL_DOMAIN="${TUNNEL_SUB}.${ZONE_NAME}"

# 第二步：授权登录
echo -e "\n${yellow}📤 执行 Cloudflare 授权登录...${reset}"
$CLOUDFLARE_BIN tunnel login

# 第三步：创建隧道
while true; do
  read -p "$(echo -e "\n${cyan}请输入隧道名称（建议英文）: ${reset}")" TUNNEL_NAME
  if [ -n "$TUNNEL_NAME" ]; then
    break
  else
    echo -e "${red}❌ 隧道名称不能为空，请重新输入${reset}"
  fi
done

echo -e "${yellow}🛠️ 正在创建隧道...${reset}"
$CLOUDFLARE_BIN tunnel create "$TUNNEL_NAME"
TUNNEL_ID=$($CLOUDFLARE_BIN tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')

if [ -z "$TUNNEL_ID" ]; then
  echo -e "${red}❌ 隧道创建失败${reset}"
  footer; exit 1
fi

# 配置隧道
echo -e "${yellow}⚙️ 正在配置隧道...${reset}"
mkdir -p /root/.cloudflared
cat > "/root/.cloudflared/config.yml" <<EOF
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json

ingress:
  - hostname: $FULL_DOMAIN
    service: http://localhost:80
  - service: http_status:404
EOF

# 设置DNS记录
echo -e "\n${yellow}🌐 正在设置DNS记录...${reset}"

# 设置CNAME记录
echo -e "${yellow}🔄 设置CNAME记录...${reset}"
CNAME_RESULT=$($CLOUDFLARE_BIN tunnel route dns "$TUNNEL_NAME" "$FULL_DOMAIN" 2>&1)

if [[ $CNAME_RESULT == *"successfully"* ]]; then
  echo -e "${green}✅ CNAME记录设置成功: ${lightpink}$FULL_DOMAIN → $TUNNEL_NAME${reset}"
else
  echo -e "${red}❌ CNAME记录设置失败: ${lightpink}$CNAME_RESULT${reset}"
fi

# 获取IP地址
IPV4=$(curl -s4 ifconfig.co || echo "")
IPV6=$(curl -s6 ifconfig.co || echo "")

# 设置A记录
if [ -n "$IPV4" ]; then
  echo -e "${yellow}🔄 设置A记录...${reset}"
  $CLOUDFLARE_BIN tunnel route ip "$TUNNEL_NAME" "$IPV4" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${green}✅ A记录设置成功: ${lightpink}$FULL_DOMAIN → $IPV4${reset}"
  else
    echo -e "${red}❌ A记录设置失败${reset}"
  fi
else
  echo -e "${yellow}⚠️ 未检测到IPv4地址，跳过A记录设置${reset}"
fi

# 设置AAAA记录
if [ -n "$IPV6" ]; then
  echo -e "${yellow}🔄 设置AAAA记录...${reset}"
  $CLOUDFLARE_BIN tunnel route ip "$TUNNEL_NAME" "$IPV6" > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo -e "${green}✅ AAAA记录设置成功: ${lightpink}$FULL_DOMAIN → $IPV6${reset}"
  else
    echo -e "${red}❌ AAAA记录设置失败${reset}"
  fi
else
  echo -e "${yellow}⚠️ 未检测到IPv6地址，跳过AAAA记录设置${reset}"
fi

echo -e "\n${green}🎉 隧道配置完成！${reset}"
echo -e "${cyan}🔗 您的隧道地址: ${lightpink}https://$FULL_DOMAIN${reset}"

footer
