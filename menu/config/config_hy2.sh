#!/bin/bash

cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
reset="\033[0m"

CONFIG_PATH="/root/VPN/config/hysteria.yaml"
mkdir -p /root/VPN/config

function header() {
echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "                              🌐 配置 HY2 节点参数"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

function footer() {
echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

function validate_uuid() {
  [[ "$1" =~ ^[0-9a-fA-F-]{36}$ ]]
}

function validate_port() {
  [[ "$1" =~ ^[0-9]{2,5}$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

clear
header

# 检查现有配置
if [ -f "$CONFIG_PATH" ]; then
  echo -e "${yellow}⚠️  检测到已有 HY2 配置文件${reset}"
  echo -e "${cyan}👉 配置路径：$CONFIG_PATH${reset}"

  if command -v jq &> /dev/null; then
    if command -v grep >/dev/null; then
      UUID=$(grep password "$CONFIG_PATH" | awk -F '"' '{print $2}')
      PORT=$(grep listen "$CONFIG_PATH" | awk '{print $2}' | sed 's/://')
      SNI=$(grep sni "$CONFIG_PATH" | awk '{print $2}')
      ALPN=$(grep -A 1 alpn "$CONFIG_PATH" | tail -n 1 | sed 's/- //')
      IPV4=$(curl -s4 ifconfig.co || echo "获取失败")
      IPV6=$(curl -s6 ifconfig.co || echo "获取失败")

      echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
      echo -e "                              🌐 当前 HY2 节点配置预览"
      echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
      echo -e " ${cyan}UUID：     ${reset}${green}$UUID${reset}"
      echo -e " ${cyan}端口号：   ${reset}${green}$PORT${reset}"
      echo -e " ${cyan}SNI 域名： ${reset}${green}$SNI${reset}"
      echo -e " ${cyan}ALPN 协议：${reset}${green}$ALPN${reset}"
      echo -e " ${cyan}IPv4：     ${reset}${green}$IPV4${reset}"
      echo -e " ${cyan}IPv6：     ${reset}${green}$IPV6${reset}"
      echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
    else
      cat "$CONFIG_PATH"
    fi
    
  else
    cat "$CONFIG_PATH"
  fi

  read -p "$(echo -e "${yellow}是否覆盖？(y/n): ${reset}")" -n 1 overwrite
  echo ""
  [[ "$overwrite" != "y" ]] && echo -e "${red}❌ 已取消操作${reset}" && footer && exit 1
fi

# UUID 输入（带循环）
while true; do
  read -p "请输入 UUID（留空自动生成）: " UUID
  if [ -z "$UUID" ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
    echo -e "${green}✔️  UUID：$UUID${reset}"
    break
  elif validate_uuid "$UUID"; then
    echo -e "${green}✔️  UUID：$UUID${reset}"
    break
  else
    echo -e "${red}❌ UUID 格式无效，请重新输入${reset}"
  fi
done

# 端口输入（带循环）
while true; do
  read -p "请输入监听端口（1024-65535，留空自动生成）: " PORT
  if [ -z "$PORT" ]; then
    PORT=$((RANDOM%30000+10000))
    echo -e "${green}✔️  端口号：$PORT${reset}"
    break
  elif validate_port "$PORT"; then
    echo -e "${green}✔️  端口号：$PORT${reset}"
    break
  else
    echo -e "${red}❌ 端口无效，请重新输入${reset}"
  fi
done

# SNI（不能为空）
while true; do
  read -p "请输入 SNI 域名（如：www.bing.com）: " SNI
  if [ -z "$SNI" ]; then
    echo -e "${red}❌ SNI 不能为空，请重新输入${reset}"
  else
    echo -e "${green}✔️  SNI 域名：$SNI${reset}"
    break
  fi
done

# ALPN（可空，自动默认）
read -p "请输入 ALPN 协议（默认 h3，直接回车使用）: " ALPN
[ -z "$ALPN" ] && ALPN="h3"
echo -e "${green}✔️  ALPN 协议：$ALPN${reset}"

# 展示公网 IP
IPV4=$(curl -s4 ifconfig.co || echo "获取失败")
IPV6=$(curl -s6 ifconfig.co || echo "获取失败")

echo -e "${yellow}📶 当前公网 IPv4：$IPV4${reset}"
echo -e "${yellow}📶 当前公网 IPv6：$IPV6${reset}"

# 写入配置
cat > "$CONFIG_PATH" <<EOF
listen: :$PORT
protocol: hysteria2
auth:
  type: password
  password: "$UUID"
tls:
  sni: $SNI
  alpn:
    - $ALPN
  insecure: true
EOF

echo -e "${green}✅ HY2 配置已生成：$CONFIG_PATH${reset}"
footer

# 返回菜单
echo ""
read -p "$(echo -e "${cyan}⓿ 返回配置菜单，按任意键继续...${reset}")"
bash /root/VPN/menu/config_node.sh
