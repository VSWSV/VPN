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

validate_domain() {
  [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]] && [[ "$1" == *"."* ]]
}

check_prerequisites() {
  # 检查cloudflared是否安装
  if [ ! -f "$CLOUDFLARE_BIN" ]; then
    echo -e "${red}❌ 未找到 cloudflared，请先安装！${reset}"
    return 1
  fi

  # 检查是否已登录
  if [ ! -f "$HOME/.cloudflared/cert.pem" ]; then
    echo -e "${yellow}⚠ 需要先登录Cloudflare...${reset}"
    $CLOUDFLARE_BIN tunnel login
    [ $? -ne 0 ] && {
      echo -e "${red}❌ 登录失败，请手动执行: cloudflared tunnel login${reset}"
      return 1
    }
  fi
  return 0
}

get_public_ip() {
  echo -e "${yellow}🔄 正在获取公网IP地址...${reset}"
  
  IPV4=$(curl -s4 --connect-timeout 5 https://api.ipify.org || 
         curl -s4 --connect-timeout 5 https://ipv4.icanhazip.com || 
         curl -s4 --connect-timeout 5 https://checkip.amazonaws.com)
  
  IPV6=$(curl -s6 --connect-timeout 5 https://api6.ipify.org || 
         curl -s6 --connect-timeout 5 https://ipv6.icanhazip.com)
  
  [ -n "$IPV4" ] && echo -e "${green}✔ IPv4地址: ${lightpink}$IPV4${reset}" || echo -e "${red}❌ 无法获取IPv4地址${reset}"
  [ -n "$IPV6" ] && echo -e "${green}✔ IPv6地址: ${lightpink}$IPV6${reset}" || echo -e "${yellow}⚠ 无法获取IPv6地址${reset}"
}

clean_tunnel_resources() {
  echo -e "${yellow}🔄 清理现有隧道资源...${reset}"
  
  rm -f "$TUNNEL_CONFIG_DIR"/*.json 2>/dev/null
  rm -f "$TUNNEL_CONFIG_DIR"/config_*.yml 2>/dev/null
  
  if $CLOUDFLARE_BIN tunnel list | grep -q "$TUNNEL_NAME"; then
    echo -e "${yellow}⚠ 删除Cloudflare上的旧隧道: $TUNNEL_NAME${reset}"
    $CLOUDFLARE_BIN tunnel delete -f "$TUNNEL_NAME" 2>/dev/null
  fi
  
  echo -e "${green}✔ 清理完成${reset}"
}

create_new_tunnel() {
  echo -e "${yellow}🛠️ 创建新隧道: $TUNNEL_NAME${reset}"
  
  if ! TUNNEL_CREATE_OUTPUT=$($CLOUDFLARE_BIN tunnel create "$TUNNEL_NAME" 2>&1); then
    echo -e "${red}❌ 隧道创建失败:${reset}"
    echo -e "${red}$TUNNEL_CREATE_OUTPUT${reset}"
    return 1
  fi
  
  TUNNEL_ID=$($CLOUDFLARE_BIN tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
  [ -z "$TUNNEL_ID" ] && {
    echo -e "${red}❌ 无法获取隧道ID${reset}"
    return 1
  }
  
  mv "$HOME/.cloudflared/$TUNNEL_ID.json" "$TUNNEL_CONFIG_DIR/" || {
    echo -e "${red}❌ 无法移动证书文件${reset}"
    return 1
  }
  
  echo -e "${green}✔ 隧道创建成功 (ID: $TUNNEL_ID)${reset}"
  return 0
}

configure_dns() {
  echo -e "\n${yellow}🌐 正在设置DNS记录...${reset}"
  
  if [ "$TUNNEL_SUB" = "@" ]; then
    echo -e "${yellow}🛑 注意：主域名将设置A/AAAA记录${reset}"
    
    if [ -n "$IPV4" ]; then
      echo -e "${yellow}🔄 设置A记录: ${lightpink}$ZONE_NAME → $IPV4${reset}"
      if $CLOUDFLARE_BIN tunnel route ip "$IPV4" "$ZONE_NAME"; then
        echo -e "${green}✔ A记录设置成功: ${lightpink}$ZONE_NAME → $IPV4${reset}"
        A_SUCCESS=true
      else
        echo -e "${red}❌ A记录设置失败${reset}"
      fi
    fi

    if [ -n "$IPV6" ]; then
      echo -e "${yellow}🔄 设置AAAA记录: ${lightpink}$ZONE_NAME → $IPV6${reset}"
      if $CLOUDFLARE_BIN tunnel route ip "$IPV6" "$ZONE_NAME"; then
        echo -e "${green}✔ AAAA记录设置成功: ${lightpink}$ZONE_NAME → $IPV6${reset}"
        AAAA_SUCCESS=true
      else
        echo -e "${red}❌ AAAA记录设置失败${reset}"
      fi
    fi
    
    [ -z "$IPV4" ] && [ -z "$IPV6" ] && {
      echo -e "${red}❌ 没有可用的IP地址用于设置DNS记录${reset}"
      return 1
    }
  else
    echo -e "${yellow}🔄 设置CNAME记录: ${lightpink}$FULL_DOMAIN → $TUNNEL_NAME${reset}"
    if $CLOUDFLARE_BIN tunnel route dns --overwrite-dns "$TUNNEL_NAME" "$FULL_DOMAIN"; then
      echo -e "${green}✔ CNAME记录设置成功: ${lightpink}$FULL_DOMAIN → $TUNNEL_NAME${reset}"
      CNAME_SUCCESS=true
    else
      echo -e "${red}❌ CNAME记录设置失败${reset}"
      return 1
    fi
  fi
  
  # 显示绑定摘要
  echo -e "\n${cyan}═════════════════════════════════════════════════════════════════════════════════${reset}"
  echo -e "${orange}                      📝 DNS记录绑定摘要                         ${reset}"
  echo -e "${cyan}═════════════════════════════════════════════════════════════════════════════════${reset}"
  
  if [ "$TUNNEL_SUB" = "@" ]; then
    [ -n "$A_SUCCESS" ] && echo -e "${green} A记录:    ${lightpink}$ZONE_NAME → $IPV4${reset}"
    [ -n "$AAAA_SUCCESS" ] && echo -e "${green} AAAA记录: ${lightpink}$ZONE_NAME → $IPV6${reset}"
  else
    [ -n "$CNAME_SUCCESS" ] && echo -e "${green} CNAME记录: ${lightpink}$FULL_DOMAIN → $TUNNEL_NAME${reset}"
  fi
  
  echo -e "${cyan}═════════════════════════════════════════════════════════════════════════════════${reset}"
  
  return 0
}

main() {
  clear
  header

  if ! check_prerequisites; then
    footer
    read -p "$(echo -e "${yellow}按回车键返回菜单...${reset}")"
    bash /root/VPN/menu/config_node.sh
    exit 1
  fi

  get_public_ip

  # 输入域名信息
  while true; do
    read -p "$(echo -e "\n${cyan}请输入主域名（如 example.com）: ${reset}")" ZONE_NAME
    if validate_domain "$ZONE_NAME"; then
      echo -e "${green}✔ 主域名: ${lightpink}$ZONE_NAME${reset}"
      break
    else
      echo -e "${red}❌ 域名格式无效（必须包含点且符合域名规则），请重新输入${reset}"
    fi
  done

  while true; do
    read -p "$(echo -e "${cyan}请输入子域名前缀（如 vpn 或 @ 表示主域名）: ${reset}")" TUNNEL_SUB
    if [ -n "$TUNNEL_SUB" ]; then
      if [ "$TUNNEL_SUB" = "@" ]; then
        FULL_DOMAIN="$ZONE_NAME"
        echo -e "${green}✔ 将配置主域名记录: ${lightpink}$ZONE_NAME${reset}"
      else
        FULL_DOMAIN="${TUNNEL_SUB}.${ZONE_NAME}"
        echo -e "${green}✔ 完整子域名: ${lightpink}$FULL_DOMAIN${reset}"
      fi
      break
    else
      echo -e "${red}❌ 子域名不能为空，请重新输入${reset}"
    fi
  done

  # 输入隧道名称
  while true; do
    read -p "$(echo -e "\n${cyan}请输入隧道名称（建议英文）: ${reset}")" TUNNEL_NAME
    if [ -n "$TUNNEL_NAME" ]; then
      echo -e "${green}✔ 隧道名称: ${lightpink}$TUNNEL_NAME${reset}"
      break
    else
      echo -e "${red}❌ 隧道名称不能为空，请重新输入${reset}"
    fi
  done

  clean_tunnel_resources
  if ! create_new_tunnel; then
    read -p "$(echo -e "${yellow}按回车键返回菜单...${reset}")"
    bash /root/VPN/menu/config_node.sh
    exit 1
  fi

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

  if ! configure_dns; then
    read -p "$(echo -e "${yellow}按回车键返回菜单...${reset}")"
    bash /root/VPN/menu/config_node.sh
    exit 1
  fi

  cat > "$CONFIG_DIR/tunnel_info_$TUNNEL_NAME" <<EOF
# Cloudflare 隧道配置信息
隧道名称: $TUNNEL_NAME
隧道ID: $TUNNEL_ID
域名: $FULL_DOMAIN
配置文件: $CONFIG_FILE
证书文件: $TUNNEL_CONFIG_DIR/$TUNNEL_ID.json
创建时间: $(date "+%Y-%m-%d %H:%M:%S")

DNS记录:
EOF

  [ "$TUNNEL_SUB" = "@" ] && {
    [ -n "$IPV4" ] && echo "A:    $ZONE_NAME → $IPV4" >> "$CONFIG_DIR/tunnel_info_$TUNNEL_NAME"
    [ -n "$IPV6" ] && echo "AAAA: $ZONE_NAME → $IPV6" >> "$CONFIG_DIR/tunnel_info_$TUNNEL_NAME"
  } || {
    echo "CNAME: $FULL_DOMAIN → $TUNNEL_NAME" >> "$CONFIG_DIR/tunnel_info_$TUNNEL_NAME"
  }

  echo -e "\n${green}🎉 隧道配置完成！${reset}"
  echo -e "${cyan}🔗 访问地址: ${lightpink}https://$FULL_DOMAIN${reset}"
  echo -e "${yellow}ℹ 配置文件保存在: $CONFIG_FILE${reset}"
  footer
  
  read -p "$(echo -e "${cyan}按回车键返回菜单...${reset}")" 
  bash /root/VPN/menu/config_node.sh
}

main
