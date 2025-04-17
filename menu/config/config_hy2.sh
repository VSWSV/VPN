#!/bin/bash

cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
reset="\033[0m"

CONFIG_PATH="/root/VPN/config/hysteria.yaml"
mkdir -p /root/VPN/config

# 美观边框
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

function get_ip() {
  curl -s6 ifconfig.co || curl -s ifconfig.me
}

# 开始
clear
header

if [ -f "$CONFIG_PATH" ]; then
  echo -e "${yellow}⚠️  已检测到现有配置文件：$CONFIG_PATH${reset}"
  read -p "是否覆盖？(y/n): " overwrite
  if [[ "$overwrite" != "y" ]]; then
    echo -e "${red}❌ 配置已取消，未覆盖原文件${reset}"
    footer
    exit 1
  fi
fi

read -p "请输入 UUID（留空自动生成）: " UUID
if [ -z "$UUID" ]; then
  UUID=$(cat /proc/sys/kernel/random/uuid)
  echo -e "${green}✔️ 自动生成 UUID：$UUID${reset}"
elif ! validate_uuid "$UUID"; then
  echo -e "${red}❌ UUID 格式无效，必须为 36 位标准 UUID${reset}"
  exit 1
fi

read -p "请输入监听端口（1024-65535，留空自动生成）: " PORT
if [ -z "$PORT" ]; then
  PORT=$((RANDOM%30000+10000))
  echo -e "${green}✔️ 自动分配端口：$PORT${reset}"
elif ! validate_port "$PORT"; then
  echo -e "${red}❌ 端口无效，请输入 1024-65535 范围内数字${reset}"
  exit 1
fi

read -p "请输入 SNI 域名（如：www.bing.com）: " SNI
[ -z "$SNI" ] && { echo -e "${red}❌ SNI 不能为空${reset}"; exit 1; }

read -p "请输入 ALPN 协议（默认 h3，直接回车使用）: " ALPN
[ -z "$ALPN" ] && ALPN="h3"

IPV4=$(curl -s4 ifconfig.co || echo "获取失败")
IPV6=$(curl -s6 ifconfig.co || echo "获取失败")

echo -e "${yellow}📶 当前公网 IPv4：$IPV4${reset}"
echo -e "${yellow}📶 当前公网 IPv6：$IPV6${reset}"

# 写入配置文件
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
