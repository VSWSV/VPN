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
  local config_file="$1"
  echo -e "\n${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "${cyan}                              🌐 现有隧道配置预览                          ${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  
  # 显示基本配置信息
  echo -e " ${lightpink}隧道名称: ${reset}${green}$TUNNEL_NAME${reset}"
  echo -e " ${lightpink}配置文件: ${reset}${green}$config_file${reset}"
  
  # 提取并显示关键配置
  if [ -f "$config_file" ]; then
    local tunnel_id=$(grep "tunnel:" "$config_file" | awk '{print $2}')
    local credentials_file=$(grep "credentials-file:" "$config_file" | awk '{print $2}')
    local domain=$(grep -A1 "ingress:" "$config_file" | grep "hostname:" | awk '{print $2}')
    
    echo -e " ${lightpink}隧道ID: ${reset}${green}$tunnel_id${reset}"
    echo -e " ${lightpink}证书文件: ${reset}${green}$credentials_file${reset}"
    echo -e " ${lightpink}绑定域名: ${reset}${green}$domain${reset}"
    
    # 显示DNS记录信息
    if [ -f "$CONFIG_DIR/tunnel_info_$TUNNEL_NAME" ]; then
      echo -e "\n${lightpink}DNS记录信息:${reset}"
      grep -A3 "DNS记录:" "$CONFIG_DIR/tunnel_info_$TUNNEL_NAME" | tail -n +2
    fi
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

# 第一步：输入隧道名称
while true; do
  read -p "$(echo -e "\n${cyan}请输入隧道名称（建议英文）: ${reset}")" TUNNEL_NAME
  if [ -n "$TUNNEL_NAME" ]; then
    # 检查是否已存在配置
    if [ -f "$TUNNEL_CONFIG_DIR/config.yml" ] || [ -f "$CONFIG_DIR/tunnel_info_$TUNNEL_NAME" ]; then
      show_existing_config "$TUNNEL_CONFIG_DIR/config.yml"
      
      while true; do
        read -p "$(echo -e "\n${yellow}检测到已有配置，是否覆盖？(y/n): ${reset}")" -n 1 overwrite
        echo ""
        case $overwrite in
          [yY]) 
            echo -e "${yellow}🔄 准备覆盖现有配置...${reset}"
            break
            ;;
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
    break
  else
    echo -e "${red}❌ 隧道名称不能为空，请重新输入${reset}"
  fi
done

# [中间部分保持不变...]

# 保存配置信息
cat > "$CONFIG_DIR/tunnel_info_$TUNNEL_NAME" <<EOF
# Cloudflare 隧道配置信息
隧道名称: $TUNNEL_NAME
隧道ID: $TUNNEL_ID
域名: $FULL_DOMAIN
配置文件: $TUNNEL_CONFIG_DIR/config.yml
证书文件: $TUNNEL_CONFIG_DIR/$TUNNEL_ID.json
创建时间: $(date "+%Y-%m-%d %H:%M:%S")

DNS记录:
CNAME: $FULL_DOMAIN → $TUNNEL_NAME
A: $FULL_DOMAIN → $IPV4
AAAA: $FULL_DOMAIN → $IPV6
EOF

# 显示最终配置信息
echo -e "\n${green}📋 最终配置信息:${reset}"
show_existing_config "$TUNNEL_CONFIG_DIR/config.yml"

footer
bash /root/VPN/menu/config_node.sh
