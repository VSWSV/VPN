#!/bin/bash
clear

# 颜色定义
green="\033[1;32m"    # 成功
yellow="\033[1;33m"   # 警告
red="\033[1;31m"      # 错误
cyan="\033[1;36m"     # 信息
orange="\033[38;5;214m" # 标题
reset="\033[0m"       # 重置

# 配置文件路径
CONFIG_INFO="/root/.cloudflared/config_info.txt"
CONFIG_YML="/root/.cloudflared/config.yml"
BACKUP_YML="/root/.cloudflared/config.yml.bak"

# 边框函数
show_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗"
  echo -e "                                   ${orange}🛠️ 隧道配置服务${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

show_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

show_header

# 配置文件检查
if [[ ! -f "$CONFIG_INFO" || ! -f "$CONFIG_YML" ]]; then
  echo -e "${red}❌ 错误：缺少配置文件${reset}"
  echo -e "${yellow}请确保以下文件存在："
  echo -e "  - $CONFIG_INFO"
  echo -e "  - $CONFIG_YML${reset}"
  show_footer
  read -p "$(echo -e "💬 ${cyan}按回车键返回主菜单...${reset}")" dummy
  exit 1
fi

# 获取Cloudflare配置
CF_API_TOKEN=$(grep "API令牌" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
DOMAIN=$(grep "顶级域名" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
TUNNEL_ID=$(grep "隧道ID" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
TUNNEL_DOMAIN="${TUNNEL_ID}.cfargotunnel.com"

# 验证Cloudflare Token
verify_result=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

if ! echo "$verify_result" | grep -q '"success":true'; then
  echo -e "${red}❌ Cloudflare Token验证失败${reset}"
  echo -e "${yellow}响应: ${verify_result}${reset}"
  exit 1
fi
echo -e "${green}✅ Cloudflare Token验证成功${reset}"

# 获取Zone ID
zone_response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

ZONE_ID=$(echo "$zone_response" | grep -o '"id":"[^"]*"' | head -n1 | cut -d':' -f2 | tr -d '"')
if [[ -z "$ZONE_ID" ]]; then
  echo -e "${red}❌ 获取Zone ID失败${reset}"
  echo -e "${yellow}响应: ${zone_response}${reset}"
  exit 1
fi

# 读取现有配置
declare -a existing_configs=()
while IFS= read -r line; do
  [[ $line =~ hostname ]] && h=$(echo "$line" | awk -F ': ' '{print $2}' | tr -d '\r')
  [[ $line =~ service ]] && s=$(echo "$line" | awk -F ': ' '{print $2}' | tr -d '\r')
  [[ $line =~ noTLSVerify ]] && t=$(echo "$line" | awk -F ': ' '{print $2}' | tr -d '\r')
  [[ $h && $s ]] && existing_configs+=("$h|$s|$t") && h="" && s="" && t=""
done < "$CONFIG_YML"

# 主配置循环
declare -a operation_logs=()
while true; do
  echo -e "\n${yellow}请选择协议类型：${reset}"
  echo -e "  ${green}1${reset} HTTP"
  echo -e "  ${green}2${reset} HTTPS"
  
  while true; do
    read -p "请输入编号: " proto_choice
    case "$proto_choice" in
      1) proto="http"; break ;;
      2) proto="https"; break ;;
      *) echo -e "${red}❌ 无效选择，请重新输入${reset}" ;;
    esac
  done

  # 子域名输入
  while true; do
    read -p "🌐 输入子域名前缀: " prefix
    prefix=$(echo "$prefix" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    if [[ -z "$prefix" ]]; then
      echo -e "${red}❌ 前缀不能为空${reset}"
    elif [[ ! "$prefix" =~ ^[a-z0-9-]+$ ]]; then
      echo -e "${red}❌ 只能包含小写字母、数字和连字符${reset}"
    else
      break
    fi
  done

  # 端口输入
  while true; do
    read -p "🔌 输入服务端口 (1-65535): " port
    [[ "$port" =~ ^[0-9]+$ ]] && ((port >= 1 && port <= 65535)) && break
    echo -e "${red}❌ 请输入1-65535之间的端口号${reset}"
  done

  # HTTPS选项
  skip_tls="false"
  if [[ "$proto" == "https" ]]; then
    read -p "🔒 跳过TLS验证? (y/n): " skip_choice
    [[ "$skip_choice" =~ ^[Yy]$ ]] && skip_tls="true"
  fi

  full_domain="$prefix.$DOMAIN"
  new_config="$full_domain|$proto://localhost:$port|$skip_tls"

  # 自动删除同域名旧配置
  for i in "${!existing_configs[@]}"; do
    if [[ "${existing_configs[$i]%%|*}" == "$full_domain" ]]; then
      # 备份配置文件
      cp "$CONFIG_YML" "$BACKUP_YML"
      
      # 删除旧配置块
      sed -i "/hostname: $full_domain/,/^\s*service: .*/d" "$CONFIG_YML"
      
      # 删除空白行
      sed -i '/^$/N;/^\n$/D' "$CONFIG_YML"
      
      echo -e "${yellow}♻️ 已移除旧配置：${existing_configs[$i]//|/ → }${reset}"
      unset "existing_configs[$i]"
    fi
  done

  # 添加新配置到文件
  TMP_FILE=$(mktemp)
  {
    # 保留文件头部
    sed -n '1,/^ingress:/p' "$CONFIG_YML"
    # 添加新配置
    echo "  - hostname: $full_domain"
    echo "    service: ${proto}://localhost:$port"
    if [[ "$proto" == "https" ]]; then
      echo "    originRequest:"
      echo "      noTLSVerify: $skip_tls"
    fi
    echo ""
    # 保留其他配置
    sed -n '/^ingress:/{n;:a;p;n;ba}' "$CONFIG_YML"
  } > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_YML"

  # 更新DNS记录
  dns_response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"CNAME\",\"name\":\"$prefix\",\"content\":\"$TUNNEL_DOMAIN\",\"ttl\":120,\"proxied\":true}")

  if echo "$dns_response" | grep -q '"success":true'; then
    echo -e "${green}✅ 域名 ${full_domain} 配置完成${reset}"
    operation_logs+=("${green}✓${reset} $full_domain → ${proto}://localhost:$port$([[ "$proto" == "https" ]] && echo " (TLS验证: $([ "$skip_tls" == "true" ] && echo "关闭" || echo "开启"))")")
  else
    echo -e "${red}❌ DNS更新失败${reset}"
    echo -e "${yellow}响应: ${dns_response}${reset}"
  fi

  # 添加到现有配置
  existing_configs+=("$new_config")

  # 继续添加？
  read -p "➕ 继续添加配置? (y/n): " continue_add
  [[ "$continue_add" =~ ^[Nn] ]] && break
done

# 操作总结
echo -e "\n${green}════════════════════ 配置完成 ════════════════════${reset}"
echo -e "${yellow}📝 操作记录：${reset}"
printf "  %s\n" "${operation_logs[@]}"
echo -e "\n${yellow}📂 配置文件: ${green}$CONFIG_YML${reset}"
echo -e "${yellow}⚙️ 备份文件: ${green}$BACKUP_YML${reset}"

show_footer
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
