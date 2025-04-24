#!/bin/bash
clear
green="\033[1;32m"; yellow="\033[1;33m"; red="\033[1;31m"
cyan="\033[1;36m"; orange="\033[38;5;214m"; reset="\033[0m"

CONFIG_DIR="/root/.cloudflared"
CONFIG_INFO="$CONFIG_DIR/config_info.txt"
CONFIG_YML="$CONFIG_DIR/config.yml"

show_top_title() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗"
  printf "${orange}%*s📡 配置子域隧道%*s\n" $(( (83 - 20) / 2 )) "" $(( (83 - 20 + 1) / 2 )) ""
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}
show_bottom_line() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

show_top_title

[[ ! -f "$CONFIG_INFO" ]] && echo -e "${red}❌ 未找到 config_info.txt${reset}" && exit 1
[[ ! -f "$CONFIG_YML" ]] && echo -e "${red}❌ 未找到 config.yml${reset}" && exit 1

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
CERT_PATH=$(grep "证书路径" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')

ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" |
  grep -o '"id":"[^"]*"' | head -n1 | cut -d':' -f2 | tr -d '"')

# 初始化 config.yml
echo "tunnel: $TUNNEL_ID" > "$CONFIG_YML"
echo "credentials-file: $CERT_PATH" >> "$CONFIG_YML"
echo "" >> "$CONFIG_YML"
echo "ingress:" >> "$CONFIG_YML"

declare -a result_lines=()

while true; do
  echo -e "${yellow}请选择服务协议类型：${reset}"
  echo "  1) HTTP"
  echo "  2) HTTPS"
  echo "  3) TCP"
  echo "  4) SSH"
  echo "  0) 返回配置节点菜单"

  read -p "协议编号: " proto_opt
  case "$proto_opt" in
    1) proto="http"; dns_type="CNAME" ;;
    2) proto="https"; dns_type="CNAME" ;;
    3) proto="tcp"; dns_type="SRV" ;;
    4) proto="ssh"; dns_type="SRV" ;;
    0) bash /root/VPN/menu/config_node.sh; exit 0 ;;
    *) echo -e "${red}❌ 无效输入${reset}"; continue ;;
  esac

  while true; do
    read -p "🧩 子域前缀（多个空格）: " input_prefixes
    read -p "🔢 服务监听端口: " port
    [[ ! "$port" =~ ^[0-9]+$ ]] && echo -e "${red}❌ 端口必须为数字${reset}" && continue

    skip_tls="false"
    [[ "$proto" == "https" ]] && read -p "🔒 跳过 TLS 验证？(y/n): " skip && [[ "$skip" =~ ^[Yy]$ ]] && skip_tls="true"

    for prefix in $(echo "$input_prefixes" | sed 's/,/ /g'); do
      full_domain="$prefix.$DOMAIN"

      echo "  - hostname: $full_domain" >> "$CONFIG_YML"
      echo "    service: ${proto}://localhost:$port" >> "$CONFIG_YML"
      [[ "$proto" == "https" ]] && echo "    originRequest:" >> "$CONFIG_YML" && echo "      noTLSVerify: $skip_tls" >> "$CONFIG_YML"

      echo -e "${cyan}🌍 正在处理 DNS：$full_domain → $TUNNEL_DOMAIN${reset}"

      exists=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$full_domain" \
        -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

      if echo "$exists" | grep -q "\"name\":\"$full_domain\""; then
        read -p "⚠️ DNS记录已存在，是否覆盖？(y/n): " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo -e "${yellow}⏩ 跳过：$full_domain${reset}" && continue
        record_id=$(echo "$exists" | grep -o '"id":"[^"]*"' | head -n1 | cut -d':' -f2 | tr -d '"')
        curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
          -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" > /dev/null
      fi

      if [[ "$dns_type" == "CNAME" ]]; then
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
          -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
          --data "{\"type\":\"CNAME\",\"name\":\"$full_domain\",\"content\":\"$TUNNEL_DOMAIN\",\"ttl\":120,\"proxied\":true}" > /dev/null
        echo -e "${green}✅ 添加成功：CNAME $full_domain → $TUNNEL_DOMAIN${reset}"
      else
        srv="_${proto}._tcp.$full_domain"
        curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
          -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
          --data "{
            \"type\":\"SRV\",
            \"name\":\"$srv\",
            \"data\":{
              \"service\":\"_$proto\",
              \"proto\":\"_tcp\",
              \"name\":\"$full_domain\",
              \"priority\":10,
              \"weight\":5,
              \"port\":$port,
              \"target\":\"$TUNNEL_DOMAIN\"
            }
          }" > /dev/null
        echo -e "${green}✅ 添加成功：SRV $srv → $TUNNEL_DOMAIN:$port${reset}"
      fi

      result_lines+=("🌐 $full_domain ｜ 协议：${proto^^} ｜ 端口：$port ｜ DNS：$dns_type → $TUNNEL_DOMAIN")
    done

    read -p "➕ 是否继续添加 ${proto^^} 服务？(y/n): " cont
    [[ "$cont" =~ ^[Nn]$ ]] && break
  done
done

echo "  - service: http_status:404" >> "$CONFIG_YML"

# 展示结果
echo -e "\n${yellow}📋 配置完成，以下为已添加服务记录：${reset}"
for line in "${result_lines[@]}"; do
  echo -e "${green}$line${reset}"
done

show_bottom_line
bash /root/VPN/menu/config_node.sh
