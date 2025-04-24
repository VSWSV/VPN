#!/bin/bash
clear

# 颜色定义
green="\033[1;32m"; yellow="\033[1;33m"; red="\033[1;31m"
cyan="\033[1;36m"; orange="\033[38;5;214m"; reset="\033[0m"

# 配置文件路径
CONFIG_INFO="/root/.cloudflared/config_info.txt"
CONFIG_YML="/root/.cloudflared/config.yml"
BACKUP_DIR="/root/.cloudflared/backups"

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 边框函数
show_header() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗"
  echo -e "                                   ${orange}🛠️ 隧道配置服务${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

show_footer() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

# 配置文件清理函数
cleanup_config() {
  # 删除重复的originRequest块
  sed -i '/originRequest:/{N;/\n\s*noTLSVerify:/d}' "$CONFIG_YML"
  # 删除多余空行
  sed -i '/^$/N;/^\n$/D' "$CONFIG_YML"
}

show_header

# 配置文件检查
[ ! -f "$CONFIG_INFO" ] && { echo -e "${red}❌ 缺少配置文件: $CONFIG_INFO${reset}"; exit 1; }
[ ! -f "$CONFIG_YML" ] && { echo -e "${red}❌ 缺少配置文件: $CONFIG_YML${reset}"; exit 1; }

# 获取配置信息
CF_API_TOKEN=$(awk -F '：' '/API令牌/{print $2}' "$CONFIG_INFO" | tr -d '\r')
DOMAIN=$(awk -F '：' '/顶级域名/{print $2}' "$CONFIG_INFO" | tr -d '\r')
TUNNEL_ID=$(awk -F '：' '/隧道ID/{print $2}' "$CONFIG_INFO" | tr -d '\r')
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

ZONE_ID=$(echo "$zone_response" | jq -r '.result[0].id')
if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" == "null" ]; then
  echo -e "${red}❌ 获取Zone ID失败${reset}"
  echo -e "${yellow}响应: ${zone_response}${reset}"
  exit 1
fi

# 配置主循环
declare -a operation_logs=()
while true; do
  # 协议选择
  echo -e "\n${yellow}请选择协议类型：${reset}"
  echo -e "  ${green}1${reset} HTTP"
  echo -e "  ${green}2${reset} HTTPS"
  
  while read -p "请输入编号: " proto_choice; do
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
  
  # 创建配置备份
  backup_file="${BACKUP_DIR}/config_$(date +%Y%m%d%H%M%S).yml"
  cp "$CONFIG_YML" "$backup_file"
  echo -e "${cyan}📦 已创建备份: ${backup_file}${reset}"

  # 删除同域名旧配置（包括可能的originRequest块）
  sed -i "/hostname: $full_domain/,/^\(\s*service:\|$\)/d" "$CONFIG_YML"
  cleanup_config

  # 添加新配置
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
    sed -n '/^ingress:/{n;:a;p;n;ba}' "$CONFIG_YML" | grep -v "^\s*$"
  } > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_YML"

  # 更新DNS记录（使用POST方法）
  dns_response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"CNAME\",\"name\":\"$prefix\",\"content\":\"$TUNNEL_DOMAIN\",\"ttl\":120,\"proxied\":true}")

  if echo "$dns_response" | jq -e '.success' >/dev/null; then
    echo -e "${green}✅ 域名 ${full_domain} 配置完成${reset}"
    operation_logs+=("${green}✓${reset} $full_domain → ${proto}://localhost:$port$([[ "$proto" == "https" ]] && echo " (TLS验证: $([ "$skip_tls" == "true" ] && echo "关闭" || echo "开启"))")")
  else
    echo -e "${red}❌ DNS更新失败${reset}"
    echo -e "${yellow}错误: $(echo "$dns_response" | jq -r '.errors[0].message')${reset}"
    echo -e "${yellow}建议: 请检查DNS记录是否已存在，或使用不同子域名前缀${reset}"
  fi

  # 继续添加？
  read -p "➕ 继续添加配置? (y/n): " continue_add
  [[ "$continue_add" =~ ^[Nn] ]] && break
done

# 最终清理
cleanup_config

# 操作总结
echo -e "\n${green}════════════════════ 配置完成 ════════════════════${reset}"
echo -e "${yellow}📝 操作记录：${reset}"
printf "  %s\n" "${operation_logs[@]}"
echo -e "\n${yellow}📂 当前配置文件: ${green}$CONFIG_YML${reset}"
echo -e "${yellow}📦 备份文件保存在: ${green}$BACKUP_DIR${reset}"

show_footer
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
