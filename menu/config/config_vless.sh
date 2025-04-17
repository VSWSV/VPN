#!/bin/bash

# 颜色定义
cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
lightpink="\033[38;5;213m"
reset="\033[0m"

CONFIG_PATH="/root/VPN/config/vless.json"
mkdir -p /root/VPN/config

function header() {
echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
echo -e "${cyan}                              🌐 配置 VLESS 节点参数                              ${reset}"
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

function validate_domain() {
  [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

function validate_alpn() {
  [[ "$1" =~ ^(h2|h3|http/1\.1|stun\.turn|webrtc|custom|http/1\.0|spdy/3\.1)$ ]]
}

function format_file_time() {
  stat -c %y "$1" 2>/dev/null | awk -F'.' '{print $1}' | sed 's/-/年/;s/-/月/;s/ /日  /;s/:/时/;s/:/分/;s/$/秒/'
}

clear
header

if [ -f "$CONFIG_PATH" ]; then
  echo -e "\n${yellow}⚠️  检测到已有 VLESS 配置文件${reset}"
  echo -e "${cyan}📂 配置路径: ${lightpink}$CONFIG_PATH${reset}"
  echo -e "${cyan}🕒 生成时间: ${lightpink}$(format_file_time "$CONFIG_PATH")${reset}\n"

  config_content=$(cat "$CONFIG_PATH" 2>/dev/null)
  UUID=$(echo "$config_content" | grep "password:" | awk -F'"' '{print $2}' || echo "获取失败")
  PORT=$(echo "$config_content" | grep "listen:" | awk '{print $2}' | tr -d ':')
  SNI=$(echo "$config_content" | grep "sni:" | awk '{print $2}' || echo "未设置")
  ALPN=$(echo "$config_content" | grep -A1 "alpn:" | tail -1 | tr -d ' -' || echo "h3")
  IPV4=$(curl -s4 ifconfig.co || echo "获取失败")
  IPV6=$(curl -s6 ifconfig.co || echo "获取失败")

  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  echo -e "${cyan}                              🌐 当前 VLESS 节点配置预览                          ${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  echo -e " ${lightpink}UUID：     ${reset}${green}$UUID${reset}"
  echo -e " ${lightpink}端口号：   ${reset}${green}$PORT${reset}"
  echo -e " ${lightpink}SNI 域名： ${reset}${green}$SNI${reset}"
  echo -e " ${lightpink}ALPN 协议：${reset}${green}$ALPN${reset}"
  echo -e " ${lightpink}IPv4：     ${reset}${green}$IPV4${reset}"
  echo -e " ${lightpink}IPv6：     ${reset}${green}$IPV6${reset}"
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"

  while true; do
    read -p "$(echo -e "\n${yellow}是否覆盖现有配置？(y/n): ${reset}")" -n 1 overwrite
    echo ""
    case $overwrite in
      [yY]) break ;;
      [nN]) 
        echo -e "${red}❌ 已取消操作${reset}"
        footer
        bash /root/VPN/menu/config_node.sh
        exit 0
        ;;
      *) echo -e "${red}❌ 无效输入，请输入 y 或 n${reset}" ;;
    esac
  done
fi

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

while true; do
  read -p "$(echo -e "\n${cyan}请输入 SNI 域名（如：www.bing.com）: ${reset}")" SNI
  if [ -z "$SNI" ]; then
    echo -e "${red}❌ SNI 不能为空，请重新输入${reset}"
  elif validate_domain "$SNI"; then
    echo -e "${green}✔️  SNI 域名：${lightpink}$SNI${reset}"
    break
  else
    echo -e "${red}❌ 域名格式无效，请重新输入（示例：example.com）${reset}"
  fi
done

while true; do
  read -p "$(echo -e "\n${cyan}请输入 ALPN 协议（默认 h3，直接回车使用）: ${reset}")" ALPN
  [ -z "$ALPN" ] && ALPN="h3"
  if validate_alpn "$ALPN"; then
    echo -e "${green}✔️  ALPN 协议：${lightpink}$ALPN${reset}"
    break
  else
    echo -e "${red}❌ 无效协议，支持：h2, h3, http/1.1${reset}"
  fi
done

echo -e "\n${yellow}📡 正在获取网络信息..."
IPV4=$(curl -s4 ifconfig.co || echo "获取失败")
IPV6=$(curl -s6 ifconfig.co || echo "获取失败")
echo -e "${yellow}📶 当前公网 IPv4：${lightpink}$IPV4${reset}"
echo -e "${yellow}📶 当前公网 IPv6：${lightpink}$IPV6${reset}"

cat > "$CONFIG_PATH" <<EOF
listen: :$PORT
protocol: vless
auth:
  type: password
  password: "$UUID"
tls:
  sni: $SNI
  alpn:
    - $ALPN
  insecure: true
EOF

chmod 777 "$CONFIG_PATH"
echo -e "\n${green}✅ VLESS 配置已生成: ${lightpink}$CONFIG_PATH${reset}"
echo -e "${green}🔓 已开放完整权限${reset}"

footer

echo ""
read -p "$(echo -e "${cyan}返回配置菜单，按任意键继续${reset}")" -n 1
bash /root/VPN/menu/config_node.sh