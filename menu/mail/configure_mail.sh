#!/bin/bash

# ...（保留之前的颜色定义和函数）

show_dns_instructions() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 🌐 DNS配置指南${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  
  cecho "$green" "请为域名 ${yellow}$domain${green} 添加以下DNS记录：\n"
  
  # 使用更清晰的表格布局
  printf "${blue}%-12s ${yellow}%-15s ${green}%-40s${reset}\n" "记录类型" "主机名" "值"
  echo -e "${blue}──────────────────────────────────────────────────────────────────────${reset}"
  printf "${green}%-12s ${reset}%-15s ${green}%-40s${reset}\n" "A记录" "@" "$(hostname -I | awk '{print $1}')"
  printf "${green}%-12s ${reset}%-15s ${green}%-40s${reset}\n" "A记录" "mail" "$(hostname -I | awk '{print $1}')"
  printf "${green}%-12s ${reset}%-15s ${green}%-40s${reset}\n" "MX记录" "@" "mail.$domain (优先级10)"
  printf "${green}%-12s ${reset}%-15s ${green}%-40s${reset}\n" "TXT记录" "@" "v=spf1 mx ~all"
  printf "${green}%-12s ${reset}%-15s ${green}%-40s${reset}\n" "TXT记录" "_dmarc" "v=DMARC1; p=none; rua=mailto:postmaster@$domain"
  printf "${green}%-12s ${reset}%-15s ${green}%-40s${reset}\n" "PTR记录" "$(hostname -I | awk '{print $1}')" "mail.$domain"
  
  cecho "$yellow" "\n🔔 重要提示："
  echo -e "${blue}• 请将${yellow}您的域名${blue}替换为实际域名（当前显示: ${yellow}$domain${blue}）"
  echo -e "${blue}• PTR记录需要联系服务器提供商设置"
  echo -e "${blue}• 测试命令: ${green}dig MX $domain${blue} 或 ${green}nslookup mail.$domain"
  
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
}

setup_multi_domain() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 🌍 多域名配置${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  
  cecho "$green" "当前主域名: ${yellow}$domain${reset}"
  cecho "$blue" "已配置子域名:"
  mysql -uroot -p"$rootpass" $DB_NAME -e "SELECT name AS '已配置域名' FROM virtual_domains;" 2>/dev/null || \
  cecho "$red" "尚未配置任何子域名"
  
  echo -e "\n${green}① 添加新子域名"
  echo -e "${green}② 设置全局收件人"
  echo -e "${green}③ 返回上级菜单${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请选择操作 [1-3]: ${reset}")" choice
  case $choice in
    1)
      read -p "$(echo -e "${yellow}✨ 请输入要添加的子域名 (如 sales.$domain): ${reset}")" subdomain
      # 验证域名格式
      if [[ $subdomain =~ ^[a-zA-Z0-9]+\.$domain$ ]]; then
        mysql -uroot -p"$rootpass" $DB_NAME -e "INSERT INTO virtual_domains (name) VALUES ('$subdomain');"
        cecho "$green" "✅ 子域名 ${yellow}$subdomain${green} 添加成功！"
        
        # 自动配置DNS提示
        cecho "$blue" "\n请为该子域名添加DNS记录："
        printf "${green}%-12s ${reset}%-15s ${green}%-40s${reset}\n" "A记录" "${subdomain%.*}" "$(hostname -I | awk '{print $1}')"
        printf "${green}%-12s ${reset}%-15s ${green}%-40s${reset}\n" "MX记录" "${subdomain%.*}" "mail.$domain (优先级10)"
      else
        cecho "$red" "❌ 格式错误！必须是主域名的子域名 (如 sales.$domain)"
      fi
      ;;
    2)
      read -p "$(echo -e "${yellow}✨ 请输入全局收件邮箱 (如 catch-all@$domain): ${reset}")" catch_all
      # 验证邮箱格式
      if [[ $catch_all =~ ^[a-zA-Z0-9._%+-]+@$domain$ ]]; then
        mysql -uroot -p"$rootpass" $DB_NAME <<EOF
INSERT INTO virtual_aliases (domain_id, source, destination) 
SELECT id, '@\$domain', '$catch_all' FROM virtual_domains WHERE name='$domain';
EOF
        cecho "$green" "✅ 全局收件设置成功！所有发送到${yellow}*@$domain${green}的邮件将转发到 ${yellow}$catch_all"
      else
        cecho "$red" "❌ 必须是有效的邮箱地址 (如 catch-all@$domain)"
      fi
      ;;
    3)
      return ;;
    *)
      cecho "$red" "无效选择！"; sleep 1 ;;
  esac
  
  read -p "$(echo -e "💬 ${cyan}按回车键继续...${reset}")" dummy
  setup_multi_domain
}

show_web_access() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 🌐 访问信息${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  
  cecho "$green" "Webmail访问地址:"
  cecho "$yellow" "https://mail.$domain/roundcube"
  
  cecho "$green" "\n管理后台地址:"
  cecho "$yellow" "https://mail.$domain/roundcube/?_task=settings"
  
  cecho "$green" "\nSMTP/POP3/IMAP服务器地址:"
  cecho "$yellow" "mail.$domain"
  cecho "$blue" "端口:"
  cecho "$yellow" "SMTP: 587 (STARTTLS), 465 (SSL)" 
  cecho "$yellow" "IMAP: 993 (SSL)"
  cecho "$yellow" "POP3: 995 (SSL)"
  
  cecho "$green" "\n📌 首次登录建议使用管理员邮箱:"
  cecho "$yellow" "postmaster@$domain"
  
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
  read -p "$(echo -e "💬 ${cyan}按回车键返回...${reset}")" dummy
}

# 在main_menu中添加新选项
main_menu() {
  clear
  echo -e "${cyan}╔═════════════════════════════════════════════════════════════════════════════════╗${reset}"
  echo -e "$orange" "                                 ⚙️ 邮局配置向导${reset}"
  echo -e "${cyan}╠═════════════════════════════════════════════════════════════════════════════════╣${reset}"
  echo -e "${green}① DNS配置指南${reset}"
  echo -e "${green}② 配置主域名${reset}"
  echo -e "${green}③ 数据库设置${reset}"
  echo -e "${green}④ 多域名配置${reset}"
  echo -e "${green}⑤ 访问信息${reset}"
  echo -e "${green}⑥ 返回主菜单${reset}"
  echo -e "${cyan}╚═════════════════════════════════════════════════════════════════════════════════╝${reset}"
  
  read -p "$(echo -e "${yellow}✨ 请选择操作 [1-6]: ${reset}")" choice
  case $choice in
    1) show_dns_instructions; main_menu ;;
    2) configure_domain; main_menu ;;
    3) setup_database; main_menu ;;
    4) setup_multi_domain; main_menu ;;
    5) show_web_access; main_menu ;;
    6) bash /root/VPN/menu/mail.sh ;;
    *) cecho "$red" "无效选择!"; sleep 1; main_menu ;;
  esac
}

# ...（保留其他函数）
