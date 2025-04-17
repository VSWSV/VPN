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
  [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

show_existing_config() {
  local config_file="$TUNNEL_CONFIG_DIR/config.yml"
  echo -e "\n${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "${cyan}                              🌐 现有隧道配置详情                          ${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  
  if [ -f "$config_file" ]; then
    echo -e " ${lightpink}配置文件: ${reset}${green}$config_file${reset}"
    
    local tunnel_id=$(grep "tunnel:" "$config_file" | awk '{print $2}')
    local credentials_file=$(grep "credentials-file:" "$config_file" | awk '{print $2}')
    local domain=$(grep -A1 "ingress:" "$config_file" | grep "hostname:" | awk '{print $2}')
    
    echo -e " ${lightpink}隧道ID: ${reset}${green}$tunnel_id${reset}"
    echo -e " ${lightpink}证书文件: ${reset}${green}$credentials_file${reset}"
    echo -e " ${lightpink}绑定域名: ${reset}${green}$domain${reset}"
    
    if [ -f "$credentials_file" ]; then
      echo -e " ${lightpink}创建时间: ${reset}${green}$(stat -c %y "$credentials_file" | cut -d'.' -f1)${reset}"
    fi
  else
    echo -e " ${red}未找到有效配置文件${reset}"
  fi
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

show_error_and_exit() {
  echo -e "\n${red}❌ 错误详情：${reset}"
  echo -e "${red}$1${reset}"
  read -p "$(echo -e "${yellow}按回车键返回菜单...${reset}")" 
  bash /root/VPN/menu/config_node.sh
  exit 1
}

clean_old_config() {
  echo -e "${yellow}🔄 正在清理旧配置...${reset}"
  rm -f "$TUNNEL_CONFIG_DIR"/config*.yml
  rm -f "$TUNNEL_CONFIG_DIR"/*.json
  rm -f "$CONFIG_DIR"/tunnel_info_*
  echo -e "${green}✔ 旧配置已清理${reset}\n"
}

# 主流程
main() {
  clear
  header

  # 检查 cloudflared
  if [ ! -f "$CLOUDFLARE_BIN" ]; then
    show_error_and_exit "未找到 cloudflared，请先安装！"
  fi

  # 自动检测现有配置
  if ls "$TUNNEL_CONFIG_DIR"/config*.yml 1> /dev/null 2>&1; then
    show_existing_config
    
    # 覆盖确认流程
    while true; do
      read -p "$(echo -e "\n${yellow}检测到已有配置，是否覆盖？(y/n): ${reset}")" overwrite
      case $overwrite in
        [yY])
          clean_old_config
          break
          ;;
        [nN])
          echo -e "${red}❌ 已取消操作${reset}"
          footer
          bash /root/VPN/menu/config_node.sh
          exit 0
          ;;
        *)
          echo -e "${red}❌ 无效输入，请输入 y 或 n${reset}"
          ;;
      esac
    done
  fi

  # 输入域名信息
  while true; do
    read -p "$(echo -e "\n${cyan}请输入主域名（如 example.com）: ${reset}")" ZONE_NAME
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

  # 输入隧道名称
  while true; do
    read -p "$(echo -e "\n${cyan}请输入隧道名称（建议英文）: ${reset}")" TUNNEL_NAME
    if [ -n "$TUNNEL_NAME" ]; then
      break
    else
      echo -e "${red}❌ 隧道名称不能为空，请重新输入${reset}"
    fi
  done

  # Cloudflare 授权登录
  echo -e "\n${yellow}📤 执行 Cloudflare 授权登录...${reset}"
  if ! LOGIN_OUTPUT=$($CLOUDFLARE_BIN tunnel login 2>&1); then
    show_error_and_exit "$LOGIN_OUTPUT"
  fi

  # 创建隧道
  echo -e "${yellow}🛠️ 正在创建隧道...${reset}"
  if ! TUNNEL_CREATE_OUTPUT=$($CLOUDFLARE_BIN tunnel create "$TUNNEL_NAME" 2>&1); then
    show_error_and_exit "$TUNNEL_CREATE_OUTPUT"
  fi

  TUNNEL_ID=$($CLOUDFLARE_BIN tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')
  if [ -z "$TUNNEL_ID" ]; then
    show_error_and_exit "无法获取隧道ID"
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
  if ! CNAME_OUTPUT=$($CLOUDFLARE_BIN tunnel route dns "$TUNNEL_NAME" "$FULL_DOMAIN" 2>&1); then
    show_error_and_exit "$CNAME_OUTPUT"
  fi
  echo -e "${green}✔ CNAME记录设置成功: ${lightpink}$FULL_DOMAIN → $TUNNEL_NAME${reset}"

  # A/AAAA记录
  IPV4=$(curl -s4 ifconfig.co || echo "")
  IPV6=$(curl -s6 ifconfig.co || echo "")

  if [ -n "$IPV4" ]; then
    echo -e "${yellow}🔄 设置A记录...${reset}"
    if ! A_OUTPUT=$($CLOUDFLARE_BIN tunnel route ip "$TUNNEL_NAME" "$IPV4" 2>&1); then
      echo -e "${red}⚠ A记录设置失败: ${lightpink}${A_OUTPUT##*ERR }${reset}"
    else
      echo -e "${green}✔ A记录设置成功: ${lightpink}$FULL_DOMAIN → $IPV4${reset}"
    fi
  fi

  if [ -n "$IPV6" ]; then
    echo -e "${yellow}🔄 设置AAAA记录...${reset}"
    if ! AAAA_OUTPUT=$($CLOUDFLARE_BIN tunnel route ip "$TUNNEL_NAME" "$IPV6" 2>&1); then
      echo -e "${red}⚠ AAAA记录设置失败: ${lightpink}${AAAA_OUTPUT##*ERR }${reset}"
    else
      echo -e "${green}✔ AAAA记录设置成功: ${lightpink}$FULL_DOMAIN → $IPV6${reset}"
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
