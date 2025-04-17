#!/bin/bash

# 颜色定义
orange="\033[38;5;208m"
cyan="\033[1;36m"
green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
lightpink="\033[38;5;213m"
reset="\033[0m"

# 统一配置目录
CONFIG_DIR="/root/VPN/config"
mkdir -p $CONFIG_DIR
CLOUDFLARE_BIN="/root/VPN/cloudflared"
TUNNEL_CONFIG_DIR="$CONFIG_DIR/cloudflared"
CERT_PATH="$TUNNEL_CONFIG_DIR/cert.pem"

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
  echo -e "\n${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "${cyan}                              🌐 检测到现有隧道配置                          ${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  
  # 查找最新配置文件
  local latest_config=$(ls -t $TUNNEL_CONFIG_DIR/config_*.yml 2>/dev/null | head -n1)
  [ -z "$latest_config" ] && latest_config="$TUNNEL_CONFIG_DIR/config.yml"
  
  if [ -f "$latest_config" ]; then
    # 显示基本配置信息
    echo -e " ${lightpink}配置文件: ${reset}${green}$latest_config${reset}"
    
    # 提取并显示关键配置
    local tunnel_id=$(grep "tunnel:" "$latest_config" | awk '{print $2}')
    local credentials_file=$(grep "credentials-file:" "$latest_config" | awk '{print $2}')
    local domain=$(grep -A1 "ingress:" "$latest_config" | grep "hostname:" | awk '{print $2}')
    
    echo -e " ${lightpink}隧道ID: ${reset}${green}$tunnel_id${reset}"
    echo -e " ${lightpink}证书文件: ${reset}${green}$credentials_file${reset}"
    echo -e " ${lightpink}绑定域名: ${reset}${green}$domain${reset}"
    
    # 显示DNS记录信息
    local latest_info=$(ls -t $CONFIG_DIR/tunnel_info_* 2>/dev/null | head -n1)
    if [ -f "$latest_info" ]; then
      echo -e "\n${lightpink}DNS记录信息:${reset}"
      grep -A3 "DNS记录:" "$latest_info" | tail -n +2
    fi
    
    # 显示创建时间
    if [ -f "$latest_info" ]; then
      echo -e " ${lightpink}创建时间: ${reset}${green}$(grep "创建时间:" "$latest_info" | cut -d':' -f2-)${reset}"
    fi
  else
    echo -e " ${red}未找到有效配置文件${reset}"
  fi
  
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

clear
header

# 检查 cloudflared
if [ ! -f "$CLOUDFLARE_BIN" ]; then
  echo -e "${red}❌ 未找到 cloudflared，请先安装！${reset}"
  footer
  bash /root/VPN/menu/config_node.sh
  exit 1
fi

# 自动检测现有配置
if ls $TUNNEL_CONFIG_DIR/config*.yml 1> /dev/null 2>&1 || ls $CONFIG_DIR/tunnel_info_* 1> /dev/null 2>&1; then
  show_existing_config
  
  # 覆盖确认流程
  while true; do
    read -p "$(echo -e "\n${yellow}检测到已有配置，是否覆盖？(y/n): ${reset}")" overwrite
    case $overwrite in
      [yY])
        echo -e "${yellow}🔄 准备覆盖现有配置...${reset}"
        # 清理旧配置
        rm -f $TUNNEL_CONFIG_DIR/config*.yml
        rm -f $TUNNEL_CONFIG_DIR/*.json
        rm -f $CONFIG_DIR/tunnel_info_*
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
        continue
        ;;
    esac
  done
fi

# 第一步：输入隧道名称
while true; do
  read -p "$(echo -e "\n${cyan}请输入隧道名称（建议英文）: ${reset}")" TUNNEL_NAME
  if [ -n "$TUNNEL_NAME" ]; then
    break
  else
    echo -e "${red}❌ 隧道名称不能为空，请重新输入${reset}"
  fi
done

# [中间部分保持不变...]

# 保存配置信息
CONFIG_FILE="$TUNNEL_CONFIG_DIR/config_$(date +%Y%m%d_%H%M%S).yml"
cat > "$CONFIG_FILE" <<EOF
tunnel: $TUNNEL_ID
credentials-file: $TUNNEL_CONFIG_DIR/$TUNNEL_ID.json

ingress:
  - hostname: $FULL_DOMAIN
    service: http://localhost:80
  - service: http_status:404
EOF

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

# 显示最终配置信息
echo -e "\n${green}🎉 隧道配置完成！${reset}"
show_existing_config

footer
bash /root/VPN/menu/config_node.sh
