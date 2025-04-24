#!/bin/bash 
clear
green="\033[1;32m"; yellow="\033[1;33m"; red="\033[1;31m"
cyan="\033[1;36m"; orange="\033[38;5;214m"; reset="\033[0m"

CONFIG_INFO="/root/.cloudflared/config_info.txt"
CONFIG_YML="/root/.cloudflared/config.yml"

show_top_title() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗"
  echo -e "                                   ${orange}📡 隧道服务${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}
show_bottom_line() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

show_top_title

# 配置文件检查
if [[ ! -f "$CONFIG_INFO" || ! -f "$CONFIG_YML" ]]; then
  echo -e "${red}❌ 缺少配置文件${reset}"
  show_bottom_line
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  bash /root/VPN/menu/config_node.sh
  exit 0
fi

CF_API_TOKEN=$(grep "API令牌" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
[[ -z "$CF_API_TOKEN" ]] && echo -e "${red}❌ API令牌为空${reset}" && exit 1

verify_result=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")
if ! echo "$verify_result" | grep -q '"success":true'; then
  echo -e "${red}❌ Cloudflare Token 验证失败${reset}"
  exit 1
fi
echo -e "${green}✅ Cloudflare Token 验证成功${reset}"

DOMAIN=$(grep "顶级域名" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
TUNNEL_ID=$(grep "隧道ID" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
TUNNEL_DOMAIN="${TUNNEL_ID}.cfargotunnel.com"

ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" |
  grep -o '"id":"[^"]*"' | head -n1 | cut -d':' -f2 | tr -d '"')

# 备份原始配置文件
cp "$CONFIG_YML" "$CONFIG_YML.bak"

declare -a result_lines=()

while true; do
  echo -e "${yellow}请选择服务协议类型：${reset}"
  echo -e "  ${yellow}❶${reset} ${green}HTTP 服务${reset}"
  echo -e "  ${yellow}❷${reset} ${green}HTTPS 服务${reset}"

  read -p "请输入编号: " proto_opt
  case "$proto_opt" in
    1) proto="http"; dns_type="CNAME" ;;
    2) proto="https"; dns_type="CNAME" ;;
    *) echo -e "${red}❌ 无效输入${reset}"; continue ;;
  esac

  read -p "🧩 子域前缀（多个空格）: " input_prefixes
  read -p "🔢 服务监听端口: " port
  [[ ! "$port" =~ ^[0-9]+$ || $port -lt 1 || $port -gt 65535 ]] && echo -e "${red}❌ 非法端口号${reset}" && continue

  skip_tls="false"
  [[ "$proto" == "https" ]] && read -p "🔒 跳过 TLS 验证？(y/n): " skip && [[ "$skip" =~ ^[Yy]$ ]] && skip_tls="true"

  # 处理每个前缀
  for prefix in $input_prefixes; do
    prefix=$(echo "$prefix" | tr 'A-Z' 'a-z')
    full_domain="$prefix.$DOMAIN"
    
    # 创建临时文件
    temp_file=$(mktemp)
    
    # 处理原始文件，删除该前缀的所有现有配置
    in_block=0
    skip_next=0
    while IFS= read -r line; do
      # 检查是否是404服务行，如果是则跳过处理
      if [[ $line == *"http_status:404"* ]]; then
        echo "$line" >> "$temp_file"
        continue
      fi
      
      # 检查是否匹配当前前缀的hostname行
      if [[ $line == *"hostname: $full_domain"* ]]; then
        in_block=1
        skip_next=1  # 跳过这一行
        continue
      fi
      
      # 如果在块中，跳过originRequest相关行
      if [[ $in_block -eq 1 ]]; then
        if [[ $line == *"originRequest:"* || $line == *"noTLSVerify:"* ]]; then
          skip_next=1
          continue
        elif [[ $line == *"service:"* ]]; then
          skip_next=1
          in_block=0  # 块结束
          continue
        fi
      fi
      
      # 如果不是要跳过的行，则写入临时文件
      if [[ $skip_next -eq 0 ]]; then
        echo "$line" >> "$temp_file"
      else
        skip_next=0
      fi
    done < "$CONFIG_YML"
    
    # 添加新的配置
    echo "  - hostname: $full_domain" >> "$temp_file"
    echo "    service: ${proto}://localhost:$port" >> "$temp_file"
    if [[ "$proto" == "https" && "$skip_tls" == "true" ]]; then
      echo "    originRequest:" >> "$temp_file"
      echo "      noTLSVerify: true" >> "$temp_file"
    fi
    
    # 确保404服务在最后
    if ! grep -q "http_status:404" "$temp_file"; then
      echo "  - service: http_status:404" >> "$temp_file"
    fi
    
    # 替换原文件
    mv "$temp_file" "$CONFIG_YML"
    
    # DNS记录处理
    echo -e "${cyan}🌍 DNS 添加中：$full_domain → $TUNNEL_DOMAIN${reset}"
    record_name="$full_domain"

    record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$record_name&type=$dns_type" \
      -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

    record_ids=$(echo "$record_info" | grep -o '"id":"[^"]*"' | cut -d':' -f2 | tr -d '"')

    if [[ -n "$record_ids" ]]; then
      echo -e "${yellow}⚠️ DNS记录已存在：$record_name${reset}"
      read -p "是否删除并重建？(y/n): " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        for rid in $record_ids; do
          curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$rid" \
            -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" > /dev/null
        done
        echo -e "${green}✅ 已删除旧记录，准备写入新记录...${reset}"
      else
        echo -e "${cyan}⏩ 跳过添加：$record_name${reset}"
        continue
      fi
    fi

    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
      -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
      --data "{\"type\":\"CNAME\",\"name\":\"$prefix\",\"content\":\"$TUNNEL_DOMAIN\",\"ttl\":120,\"proxied\":true}" > /dev/null

    result_lines+=("🌐 $full_domain ｜ 协议：${proto^^} ｜ 端口：$port ｜ DNS：$dns_type → $TUNNEL_DOMAIN")
  done

  read -p "➕ 是否继续添加其他服务？(y/n): " cont
  [[ "$cont" =~ ^[Nn]$ ]] && break
  echo ""
done

echo -e "\n${yellow}📋 以下为本次已成功添加的服务记录：${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
echo -e "${yellow}📝 复制命令可快速编辑 ▶ ${green}nano /root/.cloudflared/config.yml${reset}"
for line in "${result_lines[@]}"; do
  echo -e "  ${green}$line${reset}"
done

show_bottom_line
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/config_node.sh
