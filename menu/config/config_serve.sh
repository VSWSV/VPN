#!/bin/bash
clear

# 颜色定义
green="\033[1;32m"; yellow="\033[1;33m"; red="\033[1;31m"
cyan="\033[1;36m"; orange="\033[38;5;214m"; reset="\033[0m"

# 配置文件路径
CONFIG_INFO="/root/.cloudflared/config_info.txt"
CONFIG_YML="/root/.cloudflared/config.yml"

# 显示标题
show_top_title() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗"
  echo -e "                                   ${orange}📡 隧道服务${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

show_bottom_line() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 配置文件处理函数
update_config() {
  local domain=$1 proto=$2 port=$3 skip_tls=$4
  local temp_file=$(mktemp)
  local found=0

  # 处理现有配置
  while IFS= read -r line; do
    # 跳过相同域名的旧配置
    if [[ "$line" =~ ^\ \ -\ hostname:\ $domain$ ]]; then
      found=1
      # 跳过接下来的3行（service + originRequest）
      for _ in {1..3}; do
        read -r line || break
      done
      continue
    fi
    
    # 保留其他配置
    echo "$line" >> "$temp_file"
    
    # 在404行前插入新配置
    if [[ "$line" =~ ^\ \ -\ service:\ http_status:404$ ]]; then
      echo "  - hostname: $domain" >> "$temp_file"
      echo "    service: ${proto}://localhost:$port" >> "$temp_file"
      if [[ "$proto" == "https" ]]; then
        echo "    originRequest:" >> "$temp_file"
        echo "      noTLSVerify: $skip_tls" >> "$temp_file"
      fi
    fi
  done < "$CONFIG_YML"

  # 如果没有找到404行，则添加到最后
  if ! grep -q "http_status:404" "$temp_file"; then
    echo "  - hostname: $domain" >> "$temp_file"
    echo "    service: ${proto}://localhost:$port" >> "$temp_file"
    if [[ "$proto" == "https" ]]; then
      echo "    originRequest:" >> "$temp_file"
      echo "      noTLSVerify: $skip_tls" >> "$temp_file"
    fi
    echo "  - service: http_status:404" >> "$temp_file"
  fi

  # 替换原文件
  mv "$temp_file" "$CONFIG_YML"
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

# 获取Cloudflare Token
CF_API_TOKEN=$(grep "API令牌" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
[[ -z "$CF_API_TOKEN" ]] && echo -e "${red}❌ API令牌为空${reset}" && exit 1

# 验证Token
verify_result=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")
if ! echo "$verify_result" | grep -q '"success":true'; then
  echo -e "${red}❌ Cloudflare Token 验证失败${reset}"
  exit 1
fi
echo -e "${green}✅ Cloudflare Token 验证成功${reset}"

# 获取域名和隧道信息
DOMAIN=$(grep "顶级域名" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
TUNNEL_ID=$(grep "隧道ID" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
TUNNEL_DOMAIN="${TUNNEL_ID}.cfargotunnel.com"

# 获取Zone ID
ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" |
  grep -o '"id":"[^"]*"' | head -n1 | cut -d':' -f2 | tr -d '"')

# 使用关联数组记录结果
declare -A result_map

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
  if [[ "$proto" == "https" ]]; then
    read -p "🔒 跳过 TLS 验证？(y/n): " skip
    [[ "$skip" =~ ^[Yy]$ ]] && skip_tls="true"
  fi

  # 备份原始配置
  cp "$CONFIG_YML" "$CONFIG_YML.bak"

  for prefix in $input_prefixes; do
    prefix=$(echo "$prefix" | tr 'A-Z' 'a-z')
    full_domain="$prefix.$DOMAIN"
    
    # 更新结果映射（自动覆盖旧记录）
    result_map["$full_domain"]="🌐 $full_domain ｜ 协议：${proto^^} ｜ 端口：$port ｜ TLS验证：$([ "$skip_tls" == "true" ] && echo "跳过" || echo "启用")"
    
    # DNS记录处理
    echo -e "${cyan}🌍 正在处理DNS记录：$full_domain → $TUNNEL_DOMAIN${reset}"
    record_name="$full_domain"

    # 检查现有记录
    record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$record_name&type=$dns_type" \
      -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

    record_ids=$(echo "$record_info" | grep -o '"id":"[^"]*"' | cut -d':' -f2 | tr -d '"')

    if [[ -n "$record_ids" ]]; then
      echo -e "${yellow}⚠️ 发现已有DNS记录：$record_name${reset}"
      read -p "是否删除并重建？(y/n): " confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        for rid in $record_ids; do
          delete_result=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$rid" \
            -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")
          if echo "$delete_result" | grep -q '"success":true'; then
            echo -e "${green}✅ 成功删除旧记录: $rid${reset}"
          else
            echo -e "${red}❌ 删除记录失败: $rid${reset}"
          fi
        done
      else
        echo -e "${cyan}⏩ 保留现有DNS记录${reset}"
        continue
      fi
    fi

    # 创建新记录
    create_result=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
      -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
      --data "{\"type\":\"CNAME\",\"name\":\"$prefix\",\"content\":\"$TUNNEL_DOMAIN\",\"ttl\":120,\"proxied\":true}")

    if echo "$create_result" | grep -q '"success":true'; then
      record_id=$(echo "$create_result" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
      echo -e "${green}✅ DNS记录创建成功! (ID: $record_id)${reset}"
    else
      echo -e "${red}❌ DNS记录创建失败!${reset}"
      echo -e "${yellow}响应结果:${reset}"
      echo "$create_result" | jq .
      continue
    fi

    # 更新配置文件
    update_config "$full_domain" "$proto" "$port" "$skip_tls"
    
    # 验证配置文件
    if grep -q "hostname: $full_domain" "$CONFIG_YML"; then
      echo -e "${green}✅ 配置文件更新成功!${reset}"
    else
      echo -e "${red}❌ 配置文件更新失败，正在恢复备份...${reset}"
      mv "$CONFIG_YML.bak" "$CONFIG_YML"
    fi
  done

  read -p "➕ 是否继续添加其他服务？(y/n): " cont
  [[ "$cont" =~ ^[Nn]$ ]] && break
  echo ""
done

# 显示最终结果
echo -e "\n${yellow}📋 以下为本次已成功添加的服务记录：${reset}"
echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
for line in "${result_map[@]}"; do
  echo -e "  ${green}$line${reset}"
done

show_bottom_line
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/config_node.sh
