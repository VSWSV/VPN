#!/bin/bash
clear

green="\033[1;32m"   
yellow="\033[1;33m" 
red="\033[1;31m"  
cyan="\033[1;36m"   
soft_blue="\033[38;5;111m"  
soft_pink="\033[38;5;218m" 
orange="\033[38;5;214m"   
reset="\033[0m"      

CONFIG_INFO="/root/.cloudflared/config_info.txt"
CONFIG_YML="/root/.cloudflared/config.yml"

show_top_title() {
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "                                   ${orange}📡 隧道服务${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
}

show_bottom_line() {
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
}

show_top_title

if [[ ! -f "$CONFIG_INFO" || ! -f "$CONFIG_YML" ]]; then
  echo -e "${red}❌ 错误：缺少必要的配置文件${reset}"
  echo -e "${yellow}请确保以下文件存在："
  echo -e "  - $CONFIG_INFO"
  echo -e "  - $CONFIG_YML${reset}"
  show_bottom_line
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
  bash /root/VPN/menu/config_node.sh
  exit 1
fi

CF_API_TOKEN=$(grep "API令牌" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
if [[ -z "$CF_API_TOKEN" ]]; then
  echo -e "${red}❌ 错误：未找到有效的Cloudflare API令牌${reset}"
  exit 1
fi

verify_result=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

if ! echo "$verify_result" | grep -q '"success":true'; then
  echo -e "${red}❌ Cloudflare Token验证失败${reset}"
  echo -e "${yellow}API响应: ${verify_result}${reset}"
  exit 1
fi
echo -e "${green}✅ Cloudflare Token验证成功${reset}"

DOMAIN=$(grep "顶级域名" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
TUNNEL_ID=$(grep "隧道ID" "$CONFIG_INFO" | awk -F '：' '{print $2}' | tr -d '\r')
TUNNEL_DOMAIN="${TUNNEL_ID}.cfargotunnel.com"

zone_response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$DOMAIN" \
  -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

ZONE_ID=$(echo "$zone_response" | grep -o '"id":"[^"]*"' | head -n1 | cut -d':' -f2 | tr -d '"')
if [[ -z "$ZONE_ID" ]]; then
  echo -e "${red}❌ 错误：无法获取Zone ID${reset}"
  echo -e "${yellow}API响应: ${zone_response}${reset}"
  exit 1
fi

declare -a existing_keys=()
while read -r line; do
  [[ $line =~ hostname ]] && h=$(echo "$line" | awk -F ': ' '{print $2}' | tr -d '\r')
  [[ $line =~ service ]] && s=$(echo "$line" | awk -F ': ' '{print $2}' | tr -d '\r')
  [[ $line =~ noTLSVerify ]] && t=$(echo "$line" | awk -F ': ' '{print $2}' | tr -d '\r')
  [[ $h && $s ]] && key="${h}|${s}|${t}" && existing_keys+=("$key") && h="" && s="" && t=""
done < "$CONFIG_YML"

declare -a result_lines=()
while true; do
  echo -e "\n${yellow}请选择服务协议类型：${reset}"
  echo -e "  ${soft_blue}① ${soft_blue} ${green}HTTP 服务${reset}"
  echo -e "  ${soft_blue}② ${soft_blue} ${green}HTTPS 服务${reset}"

  while true; do
    read -p "请输入编号: " proto_opt
    case "$proto_opt" in
      1) proto="http"; dns_type="CNAME"; break ;;
      2) proto="https"; dns_type="CNAME"; break ;;
      *) echo -e "${red}❌ 无效输入，重新选择！${reset}" ;;
    esac
  done
  echo -e "${soft_pink}🔹 输入为: ${green}${proto^^}${reset}"

  while true; do
    read -p "🧩 请输入子域前缀: " prefix
    prefix=$(echo "$prefix" | tr 'A-Z' 'a-z' | tr -d ' ')
    
    if [[ -z "$prefix" ]]; then
      echo -e "${red}❌ 错误：子域前缀不能为空${reset}"
    elif [[ "$prefix" =~ [^a-z0-9-] ]]; then
      echo -e "${red}❌ 错误：子域前缀只能包含小写字母、数字和连字符(-)${reset}"
    else
      full_domain="$prefix.$DOMAIN"

      if printf '%s\n' "${existing_keys[@]}" | grep -q "^$full_domain|"; then
        echo -e "${red}❌ 错误：该域名($full_domain)已存在配置，请使用其他前缀${reset}"
      else
        echo -e "${soft_pink}🔹 输入为: ${green}$prefix${reset}"
        break
      fi
    fi
  done

  while true; do
    read -p "🔢 请输入服务监听端口 (1-65535): " port
    if [[ ! "$port" =~ ^[0-9]+$ ]] || ((port < 1 || port > 65535)); then
      echo -e "${red}❌ 错误：端口必须是1-65535之间的数字${reset}"
    else
      echo -e "${soft_pink}🔹 输入为: ${green}$port${reset}"
      break
    fi
  done

  skip_tls="false"
  if [[ "$proto" == "https" ]]; then
    while true; do
      read -p "$(echo -e "🔒 跳过TLS验证？(${green}Y${reset}/${red}N${reset}): ")" skip
      case "$skip" in
        [Yy]) skip_tls="true"; tls_status="跳过"; break ;;
        [Nn]) skip_tls="false"; tls_status="启用"; break ;;
        *) echo -e "${red}❌ 无效输入，请输入Y或N${reset}" ;;
      esac
    done
    echo -e "${soft_pink}🔹 输入为: ${green}$tls_status${reset}"
  fi

  full_domain="$prefix.$DOMAIN"
  key="$full_domain|$proto://localhost:$port|$skip_tls"

  echo -e "\n${yellow}▶ 正在处理 $full_domain ...${reset}"

  record_info=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$full_domain&type=$dns_type" \
    -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json")

  record_ids=$(echo "$record_info" | grep -o '"id":"[^"]*"' | cut -d':' -f2 | tr -d '"')

  if [[ -n "$record_ids" ]]; then
    echo -e "${yellow}⚠️ 发现已存在的DNS记录：$full_domain${reset}"
    while true; do
      read -p "$(echo -e "是否删除并重建？(${green}Y${reset}/${red}N${reset}): ")" confirm
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

  TMP_FILE=$(mktemp)
  
  {

    sed -n '1,/^ingress:/p' "$CONFIG_YML"
    
    echo "  - hostname: $full_domain"
    echo "    service: ${proto}://localhost:$port"
    if [[ "$proto" == "https" ]]; then
      echo "    originRequest:"
      echo "      noTLSVerify: $skip_tls"
    fi
    echo ""
    
    sed -n '/^ingress:/{n;:a;p;n;ba}' "$CONFIG_YML"
  } > "$TMP_FILE"

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

  existing_keys+=("$key")

  while true; do
    read -p "$(echo -e "➕ 是否继续添加其他服务？(${green}Y${reset}/${red}N${reset}): ")" cont
    case "$cont" in
      [Yy]) break ;;
      [Nn]) break 2 ;;
      *) echo -e "${red}❌ 无效输入，请输入Y或N${reset}" ;;
    esac
  done
done

  echo -e "\n${yellow}📋 本次添加的服务记录：${reset}"
  echo -e "${yellow}🛠️ 如需手动编辑，可使用命令: ${green}nano $CONFIG_YML${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"

for line in "${result_lines[@]}"; do
  echo -e "  ${green}$line${reset}"
done

show_bottom_line
read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
bash /root/VPN/menu/config_node.sh
