#!/bin/bash

# 颜色定义
orange="\033[38;5;208m"
cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
lightpink="\033[38;5;213m"
reset="\033[0m"

# 配置目录
CONFIG_DIR="/root/VPN/config"
mkdir -p $CONFIG_DIR
CLOUDFLARE_BIN="/root/VPN/cloudflared"
TUNNEL_CONFIG_DIR="$CONFIG_DIR/cloudflared"
mkdir -p $TUNNEL_CONFIG_DIR

header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "${orange}                  ☁️ Cloudflare 隧道 + 自动添加 DNS 记录（A/AAAA/CNAME）              ${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

clean_tunnel_resources() {
  echo -e "${yellow}🔄 清理现有隧道资源...${reset}"
  
  # 删除本地证书和配置文件
  rm -f /root/.cloudflared/cert.pem 2>/dev/null
  rm -f "$TUNNEL_CONFIG_DIR"/*.json 2>/dev/null
  rm -f "$TUNNEL_CONFIG_DIR"/config_*.yml 2>/dev/null
  
  # 删除Cloudflare上的隧道（如果存在）
  if $CLOUDFLARE_BIN tunnel list | grep -q "$TUNNEL_NAME"; then
    echo -e "${yellow}⚠ 删除Cloudflare上的旧隧道: $TUNNEL_NAME${reset}"
    $CLOUDFLARE_BIN tunnel delete -f "$TUNNEL_NAME" 2>/dev/null
  fi
  
  echo -e "${green}✔ 清理完成${reset}"
}

create_new_tunnel() {
  echo -e "${yellow}🛠️ 创建新隧道: $TUNNEL_NAME${reset}"
  
  # 强制清理旧隧道
  clean_tunnel_resources
  
  # 重新授权
  echo -e "${yellow}📤 重新Cloudflare授权...${reset}"
  $CLOUDFLARE_BIN tunnel login --force 2>/dev/null
  
  # 创建隧道
  if ! TUNNEL_CREATE_OUTPUT=$($CLOUDFLARE_BIN tunnel create "$TUNNEL_NAME" 2>&1); then
    echo -e "${red}❌ 隧道创建失败:${reset}"
    echo -e "${red}$TUNNEL_CREATE_OUTPUT${reset}"
    return 1
  fi
  
  TUNNEL_ID=$($CLOUDFLARE_BIN tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
  if [ -z "$TUNNEL_ID" ]; then
    echo -e "${red}❌ 无法获取隧道ID${reset}"
    return 1
  fi
  
  echo -e "${green}✔ 隧道创建成功 (ID: $TUNNEL_ID)${reset}"
  return 0
}

main() {
  clear
  header

  # 检查 cloudflared
  if [ ! -f "$CLOUDFLARE_BIN" ]; then
    echo -e "${red}❌ 未找到 cloudflared，请先安装！${reset}"
    footer
    bash /root/VPN/menu/config_node.sh
    exit 1
  fi

  # 输入域名信息
  while true; do
    read -p "$(echo -e "\n${cyan}请输入主域名（如 example.com）: ${reset}")" ZONE_NAME
    if [[ "$ZONE_NAME" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
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

  # 输入隧道名称
  while true; do
    read -p "$(echo -e "\n${cyan}请输入隧道名称（建议英文）: ${reset}")" TUNNEL_NAME
    if [ -n "$TUNNEL_NAME" ]; then
      # 立即显示输入内容
      echo -e "${green}✔ 隧道名称: ${lightpink}$TUNNEL_NAME${reset}"
      break
    else
      echo -e "${red}❌ 隧道名称不能为空，请重新输入${reset}"
    fi
  done

  # 创建隧道（自动处理冲突）
  if ! create_new_tunnel; then
    read -p "$(echo -e "${yellow}按回车键返回菜单...${reset}")"
    bash /root/VPN/menu/config_node.sh
    exit 1
  fi

  # 生成配置文件
  CONFIG_FILE="$TUNNEL_CONFIG_DIR/config_$(date +%Y%m%d_%H%M%S).yml"
  echo -e "${yellow}⚙️ 生成配置文件 $CONFIG_FILE ...${reset}"
  cat > "$CONFIG_FILE" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $TUNNEL_CONFIG_DIR/$TUNNEL_ID.json

ingress:
  - hostname: $FULL_DOMAIN
    service: http://localhost:80
  - service: http_status:404
EOF

  # 设置DNS记录
  echo -e "\n${yellow}🌐 正在设置DNS记录...${reset}"
  
  # CNAME记录
  echo -e "${yellow}🔄 设置CNAME记录...${reset}"
  if $CLOUDFLARE_BIN tunnel route dns "$TUNNEL_NAME" "$FULL_DOMAIN" 2>/dev/null; then
    echo -e "${green}✔ CNAME记录设置成功: ${lightpink}$FULL_DOMAIN → $TUNNEL_NAME${reset}"
  else
    echo -e "${red}❌ CNAME记录设置失败${reset}"
  fi

  # 获取IP地址
  IPV4=$(curl -s4 ifconfig.co || echo "")
  IPV6=$(curl -s6 ifconfig.co || echo "")

  # A记录
  if [ -n "$IPV4" ]; then
    echo -e "${yellow}🔄 设置A记录...${reset}"
    if $CLOUDFLARE_BIN tunnel route ip "$TUNNEL_NAME" "$IPV4" 2>/dev/null; then
      echo -e "${green}✔ A记录设置成功: ${lightpink}$FULL_DOMAIN → $IPV4${reset}"
    else
      echo -e "${red}❌ A记录设置失败${reset}"
    fi
  fi

  # AAAA记录
  if [ -n "$IPV6" ]; then
    echo -e "${yellow}🔄 设置AAAA记录...${reset}"
    if $CLOUDFLARE_BIN tunnel route ip "$TUNNEL_NAME" "$IPV6" 2>/dev/null; then
      echo -e "${green}✔ AAAA记录设置成功: ${lightpink}$FULL_DOMAIN → $IPV6${reset}"
    else
      echo -e "${red}❌ AAAA记录设置失败${reset}"
    fi
  fi

  # 保存配置信息
  cat > "$CONFIG_DIR/tunnel_info_$TUNNEL_NAME" <<EOF
# Cloudflare 隧道配置信息
隧道名称: $TUNNEL_NAME
隧道ID: $TUNNEL_ID
域名: $FULL_DOMAIN
配置文件: $CONFIG_FILE
证书文件: $TUNNEL_CONFIG_DIR/$TUNNEL_ID.json
创建时间: $(date "+%Y-%m-%d %H:%M:%S")

DNS记录:
CNAME: $FULL_DOMAIN → $TUNNEL_NAME
A: $FULL_DOMAIN → $IPV4
AAAA: $FULL_DOMAIN → $IPV6
EOF

  echo -e "\n${green}🎉 隧道配置完成！${reset}"
  echo -e "${cyan}🔗 访问地址: ${lightpink}https://$FULL_DOMAIN${reset}"
  footer
  
  # 返回菜单前暂停
  read -p "$(echo -e "${cyan}按回车键返回菜单...${reset}")" 
  bash /root/VPN/menu/config_node.sh
}

# 执行主流程
main
