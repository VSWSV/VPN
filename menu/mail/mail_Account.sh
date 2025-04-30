#!/bin/bash
# ==============================================
# 邮箱账户管理脚本 FINAL V3（修复全部功能异常）
# 适配 Ubuntu 20.04+，MySQL 后端，Roundcube/Postfix 环境
# ==============================================

green="\033[1;32m"
yellow="\033[1;33m"
red="\033[1;31m"
blue="\033[1;34m"
reset="\033[0m"

function draw_line() {
    echo -e "${blue}================================================================================${reset}"
}

function success() {
    echo -e "${green}[成功]${reset} $1"
}

function warn() {
    echo -e "${yellow}[警告]${reset} $1"
}

function error_exit() {
    echo -e "${red}[错误]${reset} $1"
    exit 1
}

function get_db_info() {
    draw_line
    echo -e "${green}请输入数据库连接信息${reset}"
    read -p "请输入数据库名: " DBNAME
    [[ -z "$DBNAME" ]] && error_exit "数据库名不能为空！"
    read -p "请输入数据库用户名: " DBUSER
    [[ -z "$DBUSER" ]] && error_exit "数据库用户名不能为空！"
    read -p "请输入数据库用户密码: " DBPASS
    [[ -z "$DBPASS" ]] && error_exit "数据库密码不能为空！"

    export DBNAME
    export DBUSER
    export DBPASS

    mysql -u${DBUSER} -p${DBPASS} -e "use ${DBNAME}" 2>/dev/null
    [[ $? -ne 0 ]] && error_exit "无法连接到数据库，请检查信息是否正确！"
    success "数据库连接正常。"
    draw_line
}

function create_account() {
    draw_line
    echo -e "${green}创建新邮箱账户${reset}"
    read -p "请输入邮箱用户名 (不含@域名，例如 admin): " USERNAME
    [[ -z "$USERNAME" ]] && error_exit "用户名不能为空！"
    read -p "请输入邮箱域名 (例如 vswsv.com): " DOMAIN
    [[ -z "$DOMAIN" ]] && error_exit "域名不能为空！"
    read -p "请输入邮箱用户备注名: " NAME
    [[ -z "$NAME" ]] && NAME="$USERNAME"
    read -p "请输入邮箱密码（可见）: " PASSWORD
    [[ -z "$PASSWORD" ]] && error_exit "密码不能为空！"
    if [[ "$PASSWORD" =~ $'\n' || "$PASSWORD" =~ $'\r' ]]; then
        error_exit "密码中不能包含换行或回车字符，请重新输入。"
    fi

    DOMAIN_ID=$(mysql -u${DBUSER} -p${DBPASS} -Nse "SELECT id FROM ${DBNAME}.domain WHERE name='${DOMAIN}' AND active=1;" | head -n1)
    [[ -z "$DOMAIN_ID" ]] && error_exit "未找到域名 ${DOMAIN}，请先在数据库中添加！"

    ENCRYPT_PASS=$(doveadm pw -s MD5-CRYPT -p "$PASSWORD")
    MAILDIR="${DOMAIN}/${USERNAME}/"
    EMAIL="${USERNAME}@${DOMAIN}"

    mysql -u${DBUSER} -p${DBPASS} -e "INSERT INTO ${DBNAME}.mailbox (domain_id, username, password, name, maildir, active) VALUES (${DOMAIN_ID}, '${EMAIL}', '${ENCRYPT_PASS}', '${NAME}', '${MAILDIR}', 1);"

    mkdir -p /var/mail/vhosts/${DOMAIN}/${USERNAME}
    chown -R vmail:vmail /var/mail/vhosts/${DOMAIN}/${USERNAME}

    success "邮箱账户 ${EMAIL} 创建完成。"
    draw_line
}

function delete_account() {
    draw_line
    echo -e "${green}删除邮箱账户${reset}"
    read -p "请输入要删除的完整邮箱地址 (例如 admin@vswsv.com): " EMAIL
    [[ -z "$EMAIL" ]] && error_exit "邮箱地址不能为空！"

    USERNAME=$(echo $EMAIL | cut -d@ -f1)
    DOMAIN=$(echo $EMAIL | cut -d@ -f2)

    ID=$(mysql -u${DBUSER} -p${DBPASS} -Nse "SELECT m.id FROM ${DBNAME}.mailbox m JOIN ${DBNAME}.domain d ON m.domain_id=d.id WHERE m.username='${EMAIL}' AND d.name='${DOMAIN}';" | head -n1)
    if [[ -z "$ID" ]]; then
        warn "未找到邮箱账户 ${EMAIL}，跳过删除。"
    else
        mysql -u${DBUSER} -p${DBPASS} -e "DELETE FROM ${DBNAME}.mailbox WHERE id=${ID};"
        rm -rf /var/mail/vhosts/${DOMAIN}/${USERNAME}
        success "邮箱账户 ${EMAIL} 已删除。"
    fi
    draw_line
}

function change_password() {
    draw_line
    echo -e "${green}修改邮箱账户密码${reset}"
    read -p "请输入要修改密码的完整邮箱地址 (例如 admin@vswsv.com): " EMAIL
    [[ -z "$EMAIL" ]] && error_exit "邮箱地址不能为空！"

    USERNAME=$(echo $EMAIL | cut -d@ -f1)
    DOMAIN=$(echo $EMAIL | cut -d@ -f2)

    ID=$(mysql -u${DBUSER} -p${DBPASS} -Nse "SELECT m.id FROM ${DBNAME}.mailbox m JOIN ${DBNAME}.domain d ON m.domain_id=d.id WHERE m.username='${EMAIL}' AND d.name='${DOMAIN}';" | head -n1)
    [[ -z "$ID" ]] && error_exit "未找到邮箱账户 ${EMAIL}！"

    read -p "请输入新密码（可见）: " NEWPASS
    [[ -z "$NEWPASS" ]] && error_exit "新密码不能为空！"
    ENCRYPT_NEWPASS=$(doveadm pw -s MD5-CRYPT -p "$NEWPASS")
    mysql -u${DBUSER} -p${DBPASS} -e "UPDATE ${DBNAME}.mailbox SET password='${ENCRYPT_NEWPASS}' WHERE id=${ID};"

    success "邮箱账户 ${EMAIL} 密码修改成功。"
    draw_line
}

function set_catch_all() {
    draw_line
    echo -e "${green}设置Catch-All全域收件账户${reset}"
    read -p "请输入域名 (例如 vswsv.com): " DOMAIN
    [[ -z "$DOMAIN" ]] && error_exit "域名不能为空！"
    read -p "请输入转发到的邮箱 (例如 admin@vswsv.com): " TARGET
    [[ -z "$TARGET" ]] && error_exit "目标邮箱不能为空！"

    DOMAIN_ID=$(mysql -u${DBUSER} -p${DBPASS} -Nse "SELECT id FROM ${DBNAME}.domain WHERE name='${DOMAIN}' AND active=1;" | head -n1)
    [[ -z "$DOMAIN_ID" ]] && error_exit "未找到域名 ${DOMAIN}！"

    mysql -u${DBUSER} -p${DBPASS} -e "DELETE FROM ${DBNAME}.alias WHERE source='@${DOMAIN}';"
    mysql -u${DBUSER} -p${DBPASS} -e "INSERT INTO ${DBNAME}.alias (domain_id, source, destination, active) VALUES (${DOMAIN_ID}, '@${DOMAIN}', '${TARGET}', 1);"

    success "Catch-All 设置成功，所有发往 ${DOMAIN} 未匹配的邮件将转发到 ${TARGET}。"
    draw_line
}

function list_accounts() {
    draw_line
    echo -e "${green}当前所有邮箱账户：${reset}"
    SAMPLE_EMAIL=$(mysql -u${DBUSER} -p${DBPASS} -Nse "SELECT username FROM ${DBNAME}.mailbox LIMIT 1;" 2>/dev/null)
    if [[ "$SAMPLE_EMAIL" == *@* ]]; then
        mysql -u${DBUSER} -p${DBPASS} -e "SELECT username AS 邮箱地址, name AS 用户名 FROM ${DBNAME}.mailbox WHERE active=1;"
    else
        mysql -u${DBUSER} -p${DBPASS} -e "SELECT CONCAT(m.username, '@', d.name) AS 邮箱地址, m.name AS 用户名 FROM ${DBNAME}.mailbox m JOIN ${DBNAME}.domain d ON m.domain_id=d.id WHERE m.active=1;"
    fi
    draw_line
}

function main_menu() {
    while true; do
        draw_line
        echo -e "${green}📬 邮箱账户管理系统${reset}"
        echo "1. 创建邮箱账户"
        echo "2. 删除邮箱账户"
        echo "3. 修改邮箱账户密码"
        echo "4. 设置Catch-All全域收件"
        echo "5. 列出所有邮箱账户"
        echo "0. 退出"
        read -p "请输入选项编号: " CHOICE
        case $CHOICE in
            1) create_account ;;
            2) delete_account ;;
            3) change_password ;;
            4) set_catch_all ;;
            5) list_accounts ;;
            0) exit 0 ;;
            *) warn "无效选项，请重新输入！" ;;
        esac
    done
}

function main() {
    get_db_info
    main_menu
}

main
