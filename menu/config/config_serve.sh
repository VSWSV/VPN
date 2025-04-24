#!/bin/bash
clear

# 颜色定义
green="\033[1;32m"   # 成功 - 绿色
yellow="\033[1;33m"  # 警告/需确认 - 黄色
red="\033[1;31m"     # 错误 - 红色
cyan="\033[1;36m"    # 跳过/信息 - 青色
blue="\033[1;34m"    # 选项 - 蓝色
pink="\033[1;35m"    # 输入反馈 - 粉色
orange="\033[38;5;214m"  # 标题 - 橙色
reset="\033[0m"      # 重置颜色

# 文件路径
CONFIG_INFO="/root/.cloudflared/config_info.txt"
CONFIG_YML="/root/.cloudflared/config.yml"

# 显示标题函数
show_top_title() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗"
  echo -e "                                   ${orange}📡 隧道服务${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

show_bottom_line() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

show_top_title

# 1. 配置文件检查
if [[ ! -f "$CONFIG_INFO" || ! -f "$CONFIG_YML" ]]; then
  echo -e "${red}❌ 错误：缺少必要的配置文件${reset}"
  echo -e "${yellow}请确保以下文件存在："
  echo -e "  - $CONFIG_INFO"
  echo -e "  - $CONFIG_YML${reset}"
  show_bottom_line
  read -p "$(echo -e "💬 ${cyan}按回车键返回主菜单...${reset}")" dummy
  bash /root/VPN/menu/config_node.sh
  exit 1
fi

# 2. 获取配置信息
CF_API_TOKEN=$(grep "API令牌" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
if [[ -z "$CF_API_TOKEN" ]]; then
  echo -e "${red}❌ 错误：未找到有效的Cloudflare API令牌${reset}"
  exit 1
fi

# 3. 验证Cloudflare Token
verify_result=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

if ! echo "$verify_result" | grep -q '"success":true'; then
  echo -e "${red}❌ Cloudflare Token验证失败${reset}"
  echo -e "${yellow}API响应: ${verify_result}${reset}"
  exit 1
fi
echo -e "${green}✅ Cloudflare Token验证成功${reset}"

# 4. 获取域名和隧道信息
DOMAIN=$(grep "顶级域名" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
TUNNEL_ID=$(grep "隧道ID" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
TUNNEL_DOMAIN="${TUNNEL_ID}.cfargotunnel.com"

# 5. 获取Zone ID
zone_response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

ZONE_ID=$(echo "$zone_response" | grep -o '"id":"[^"]*"' | head -n1 | cut -d':' -f2 | tr -d '"')
if [[ -z "$ZONE_ID" ]]; then
  echo -e "${red}❌ 错误：无法获取Zone ID${reset}"
  echo -e "${yellow}API响应: ${zone_response}${reset}"
  exit 1
fi

# 6. 读取现有配置
declare -a existing_keys=()
while read -r line; do
  [[ $line =~ hostname ]] && h=$(echo "$line" | awk -F ': ' '{print $2}' | tr -d '\r')
  [[ $line =~ service ]] && s=$(echo "$line" | awk -F ': ' '{print $2}' | tr -d '\r')
  [[ $line =~ noTLSVerify ]] && t=$(echo "$line" | awk -F ': ' '{print $2}' | tr -d '\r')
  [[ $h && $s ]] && key="${h}|${s}|${t}" && existing_keys+=("$key") && h="" && s="" && t=""
done < "$CONFIG_YML"

# 7. 主配置循环
declare -a result_lines=()
while true; do
  echo -e "\n${yellow}请选择服务协议类型：${reset}"
  echo -e "  ${blue}①${blue} ${green}HTTP 服务${reset}"
  echo -e "  ${blue}②${blue} ${green}HTTPS 服务${reset}"

  while true; do
    read -p "请输入编号: " proto_opt
    case "$proto_opt" in
      1) proto="http"; dns_type="CNAME"; break ;;
      2) proto="https"; dns_type="CNAME"; break ;;
      *) echo -e "${red}❌ 无效输入，请输入①或②${reset}" ;;
    esac
  done
  echo -e "${pink}🔹 输入为: ${green}${proto^^}${reset}"

  # 子域前缀输入验证
  while true; do
    read -p "🧩 请输入子域前缀: " prefix
    prefix=$(echo "$prefix" | tr 'A-Z' 'a-z' | tr -d ' ')
    
    if [[ -z "$prefix" ]]; then
      echo -e "${red}❌ 错误：子域前缀不能为空${reset}"
    elif [[ "$prefix" =~ [^a-z0-9-] ]]; then
      echo -e "${red}❌ 错误：子域前缀只能包含小写字母、数字和连字符(-)${reset}"
    else
      full_domain="$prefix.$DOMAIN"
      # 检查是否已存在相同域名的配置
      if printf '%s\n' "${existing_keys[@]}" | grep -q "^$full_domain|"; then
        echo -e "${red}❌ 错误：该域名($full_domain)已存在配置，请使用其他前缀${reset}"
      else
        echo -e "${pink}🔹 输入为: ${green}$prefix${reset}"
        break
      fi
    fi
  done

  # 端口输入验证
  while true; do
    read -p "🔢 请输入服务监听端口 (1-65535): " port
    if [[ ! "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
      echo -e "${red}❌ 错误：端口必须是1-65535之间的数字${reset}"
    else
      echo -e "${pink}🔹 输入为: ${green}$port${reset}"
      break
    fi
  done

  # HTTPS额外选项
  skip_tls="false"
  if [[ "$proto" == "https" ]]; then
    while true; do
      read -p "🔒 跳过TLS验证？(${green}Y${reset}/${red}N${reset}): " skip
      case "$skip" in
        [Yy]) skip_tls="true"; tls_status="跳过"; break ;;
        [Nn]) skip_tls="false"; tls_status="启用"; break ;;
        *) echo -e "${red}❌ 无效输入，请输入Y或N${reset}" ;;
      esac
    done
    echo -e "${pink}🔹 输入为: ${green}$tls_status${reset}"
  fi

  full_domain="$prefix.$DOMAIN"
  key="$full_domain|$proto://localhost:$port|$skip_tls"

  echo -e "\n${yellow}▶ 正在处理 $full_domain ...${reset}"

  # 检查现有DNS记录
  record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$full_domain&type=$dns_type" \
    -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

  record_ids=$(echo "$record_info" | grep -o '"id":"[^"]*"' | cut -d':' -f2 | tr -d '"')

  # 处理已存在记录
  if [[ -n "$record_ids" ]]; then
    echo -e "${yellow}⚠️ 发现已存在的DNS记录：$full_domain${reset}"
    while true; do
      read -p "是否删除并重建？(${green}Y${reset}/${red}N${reset}): " confirm
      case "$confirm" in
        [Yy]) 
          for rid in $record_ids; do
            delete_result=$(curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$rid" \
              -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")
            
            if echo "$delete_result" | grep -q '"success":true'; then
              echo -e "${green}✅ 成功删除DNS记录: $full_domain (ID: $rid)${reset}"
            else
              echo -e "${red}❌ 删除DNS记录失败: $full_domain${reset}"
              echo -e "${yellow}响应: ${delete_result}${reset}"
              exit 1
            fi
          done
          break
          ;;
        [Nn])
          echo -e "${cyan}⏩ 跳过：用户选择保留现有DNS记录${reset}"
          continue 2
          ;;
        *)
          echo -e "${red}❌ 无效输入，请输入Y或N${reset}"
          ;;
      esac
    done
  fi

  # 创建临时文件
  TMP_FILE=$(mktemp)
  
  # 更新配置文件
  {
    # 保留文件头部
    sed -n '1,/^ingress:/p' "$CONFIG_YML"
    
    # 添加新配置（直接跟在ingress:下方，后面加空行）
    echo "  - hostname: $full_domain"
    echo "    service: ${proto}://localhost:$port"
    if [[ "$proto" == "https" ]]; then
      echo "    originRequest:"
      echo "      noTLSVerify: $skip_tls"
    fi
    echo ""
    
    # 保留原有配置（跳过开头的ingress:行）
    sed -n '/^ingress:/{n;:a;p;n;ba}' "$CONFIG_YML"
  } > "$TMP_FILE"

  # 验证并替换配置文件
  if ! grep -q "hostname: $full_domain" "$TMP_FILE"; then
    echo -e "${red}❌ 错误：配置文件更新验证失败${reset}"
    exit 1
  fi

  if mv "$TMP_FILE" "$CONFIG_YML"; then
    echo -e "${green}✅ 配置文件更新成功${reset}"
  else
    echo -e "${red}❌ 错误：配置文件更新失败${reset}"
    exit 1
  fi

  # 创建DNS记录
  dns_data="{\"type\":\"CNAME\",\"name\":\"$prefix\",\"content\":\"$TUNNEL_DOMAIN\",\"ttl\":120,\"proxied\":true}"
  dns_response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" \
    --data "$dns_data")

  if echo "$dns_response" | grep -q '"success":true'; then
    if [[ "$proto" == "http" ]]; then
      result_lines+=("🌐 $full_domain ｜ ${proto^^} ｜ 端口:$port")
    else
      result_lines+=("🌐 $full_domain ｜ ${proto^^} ｜ 端口:$port ｜ TLS验证:$([ "$skip_tls" = "true" ] && echo "跳过" || echo "启用")")
    fi
    echo -e "${green}✅ DNS记录创建成功: $full_domain → $TUNNEL_DOMAIN${reset}"
  else
    echo -e "${red}❌ DNS记录创建失败: $full_domain${reset}"
    echo -e "${yellow}响应: ${dns_response}${reset}"
    echo -e "${yellow}请求数据: ${dns_data}${reset}"
    exit 1
  fi

  # 添加到现有配置检查列表
  existing_keys+=("$key")

  # 询问是否继续
  while true; do
    read -p "➕ 是否继续添加其他服务？(${green}Y${reset}/${red}N${reset}): " cont
    case "$cont" in
      [Yy]) break ;;
      [Nn]) break 2 ;;
      *) echo -e "${red}❌ 无效输入，请输入Y或N${reset}" ;;
    esac
  done
done

# 8. 显示结果摘要
echo -e "\n${green}════════════════════ 操作完成 ════════════════════${reset}"
echo -e "${yellow}📋 本次添加的服务记录：${reset}"
for line in "${result_lines[@]}"; do
  echo -e "  ${green}$line${reset}"
done

echo -e "\n${yellow}📝 配置文件位置: ${green}$CONFIG_YML${reset}"
echo -e "${yellow}🛠️ 如需手动编辑，可使用命令: ${green}nano $CONFIG_YML${reset}"

show_bottom_line
read -p "$(echo -e "💬 ${cyan}按回车键返回主菜单...${reset}")" dummy
bash /root/VPN/menu/config_node.sh
