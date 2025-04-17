#!/bin/bash

# Color definitions
cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
lightpink="\033[38;5;213m"  # Changed to lighter pink
reset="\033[0m"

CONFIG_PATH="/root/VPN/config/hysteria.yaml"
mkdir -p /root/VPN/config

function header() {
echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "${cyan}                              🌐 配置 HY2 节点参数                              ${reset}"
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
  echo -e "\n${yellow}⚠️  检测到已有 HY2 配置文件${reset}"
  echo -e "${cyan}📂 配置路径: ${lightpink}$CONFIG_PATH${reset}\n"

  # 使用更可靠的解析方式
  config_content=$(cat "$CONFIG_PATH" 2>/dev/null)
  UUID=$(echo "$config_content" | grep -oP '(?<=password: ")[^"]+' || echo "获取失败")
  PORT=$(echo "$config_content" | grep -oP '(?<=listen: :)[0-9]+' || echo "获取失败")
  SNI=$(echo "$config_content" | grep -oP '(?<=sni: )[^ ]+' || echo "未设置")
  ALPN=$(echo "$config_content" | grep -oP '(?<=alpn:\n\s+- )[^ ]+' || echo "h3")
  IPV4=$(curl -s4 ifconfig.co || echo "获取失败")
  IPV6=$(curl -s6 ifconfig.co || echo "获取失败")

  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "${cyan}                              🌐 当前 HY2 节点配置预览                          ${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  echo -e " ${lightpink}UUID：     ${reset}${green}$UUID${reset}"
  echo -e " ${lightpink}端口号：   ${reset}${green}$PORT${reset}"
  echo -e " ${lightpink}SNI 域名： ${reset}${green}$SNI${reset}"
  echo -e " ${lightpink}ALPN 协议：${reset}${green}$ALPN${reset}"
  echo -e " ${lightpink}IPv4：     ${reset}${green}$IPV4${reset}"
  echo -e " ${lightpink}IPv6：     ${reset}${green}$IPV6${reset}"
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

  read -p "$(echo -e "\n${yellow}是否覆盖现有配置？(y/n): ${reset}")" -n 1 overwrite
  echo ""
  [[ "$overwrite" != "y" ]] && echo -e "${red}❌ 已取消操作${reset}" && footer && exit 1
fi

# UUID 输入（带循环）
while true; do
  read -p "$(echo -e "\n${cyan}请输入 UUID（留空自动生成）: ${reset}")" UUID
  if [ -z "$UUID" ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
    echo -e "${green}✔️  UUID：${lightpink}$UUID${reset}"
    break
  elif validate_uuid "$UUID"; then
    echo -e "${green}✔️  UUID：${lightpink}$UUID${reset}"
    break
  else
    echo -e "${red}❌ UUID 格式无效，请重新输入${reset}"
  fi
done

# 端口输入（带循环）
while true; do
  read -p "$(echo -e "\n${cyan}请输入监听端口（1024-65535，留空自动生成）: ${reset}")" PORT
  if [ -z "$PORT" ]; then
    PORT=$((RANDOM%30000+10000))
    echo -e "${green}✔️  端口号：${lightpink}$PORT${reset}"
    break
  elif validate_port "$PORT"; then
    echo -e "${green}✔️  端口号：${lightpink}$PORT${reset}"
    break
  else
    echo -e "${red}❌ 端口无效，请重新输入${reset}"
  fi
done

# SNI（不能为空）
while true; do
  read -p "$(echo -e "\n${cyan}请输入 SNI 域名（如：www.bing.com）: ${reset}")" SNI
  if [ -z "$SNI" ]; then
    echo -e "${red}❌ SNI 不能为空，请重新输入${reset}"
  else
    echo -e "${green}✔️  SNI 域名：${lightpink}$SNI${reset}"
    break
  fi
done

# ALPN（可空，自动默认）
read -p "$(echo -e "\n${cyan}请输入 ALPN 协议（默认 h3，直接回车使用）: ${reset}")" ALPN
[ -z "$ALPN" ] && ALPN="h3"
echo -e "${green}✔️  ALPN 协议：${lightpink}$ALPN${reset}"

# 展示公网 IP
echo -e "\n${yellow}📡 正在获取网络信息..."
IPV4=$(curl -s4 ifconfig.co || echo "获取失败")
IPV6=$(curl -s6 ifconfig.co || echo "获取失败")
echo -e "${yellow}📶 当前公网 IPv4：${lightpink}$IPV4${reset}"
echo -e "${yellow}📶 当前公网 IPv6：${lightpink}$IPV6${reset}"

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

echo -e "\n${green}✅ HY2 配置已生成: ${lightpink}$CONFIG_PATH${reset}"
footer

# 返回菜单
echo ""
read -p "$(echo -e "${cyan}⓿ 返回配置菜单，按任意键继续...${reset}")" -n 1
bash /root/VPN/menu/config_node.sh
