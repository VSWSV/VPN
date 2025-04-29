#!/bin/bash

echo "=============================================="
echo "      邮箱账户管理脚本 (管理虚拟邮箱账户)       "
echo "=============================================="

read -p "请输入要操作的域名 (如 example.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    echo "域名不能为空，脚本结束。"
    exit 1
fi
echo "当前域名: $DOMAIN"

echo "请选择操作："
echo "  1) 创建邮箱账户"
echo "  2) 删除邮箱账户"
echo "  3) 修改邮箱密码"
echo "  4) 设置全域收件 (Catch-all)"
echo "  5) 列出所有邮箱账户"
read -p "请输入选项 [1-5]: " action

# 数据库连接信息（应与配置脚本中一致）
DBHOST="localhost"
DBNAME="mailserver"
DBUSER="mailuser"   # 请替换为实际的数据库用户名
DBPASS="YOUR_DB_PASSWORD"  # 请替换为实际的数据库密码

execute_sql() {
    # 在实际环境中，可能需要屏蔽密码回显或更安全的存储密码方式
    mysql -h"$DBHOST" -u"$DBUSER" -p"$DBPASS" "$DBNAME" -e "$1"
}

case $action in
    1)
        echo "----------------------------------------------"
        echo "创建邮箱账户"
        read -p "请输入邮箱地址 (如 user@$DOMAIN): " EMAIL
        if [[ "$EMAIL" != *@* ]]; then
            echo "邮箱格式不正确，退出。"
            exit 1
        fi
        USER=${EMAIL%@*}
        DOMAIN_INPUT=${EMAIL#*@}
        if [[ "$DOMAIN_INPUT" != "$DOMAIN" ]]; then
            echo "错误：邮箱域名必须是 $DOMAIN"
            exit 1
        fi
        read -s -p "请输入密码: " PASS
        echo ""
        # 使用 Dovecot 生成加密密码
        ENC_PASS=$(doveadm pw -s SHA512-CRYPT -p "$PASS")
        # 插入到 mailbox 表
        SQL="INSERT INTO mailbox (user, domain, password) VALUES ('$USER', '$DOMAIN', '$ENC_PASS');"
        execute_sql "$SQL"
        # 插入到 alias 表，创建同名别名便于投递
        SQL="INSERT INTO alias (address, goto) VALUES ('$EMAIL', '$EMAIL');"
        execute_sql "$SQL"
        # 创建 Maildir 目录
        MAILDIR="/var/mail/vhosts/$DOMAIN/$USER"
        mkdir -p "$MAILDIR"
        chown -R dovecot:dovecot "/var/mail/vhosts/$DOMAIN"
        echo "已创建邮箱账户：$EMAIL"
        ;;
    2)
        echo "----------------------------------------------"
        echo "删除邮箱账户"
        read -p "请输入要删除的邮箱地址 (如 user@$DOMAIN): " EMAIL
        USER=${EMAIL%@*}
        DOMAIN_INPUT=${EMAIL#*@}
        if [[ "$DOMAIN_INPUT" != "$DOMAIN" ]]; then
            echo "错误：邮箱域名必须是 $DOMAIN"
            exit 1
        fi
        # 删除数据库记录
        SQL="DELETE FROM mailbox WHERE user = '$USER' AND domain = '$DOMAIN';"
        execute_sql "$SQL"
        SQL="DELETE FROM alias WHERE goto = '$EMAIL' OR address = '$EMAIL';"
        execute_sql "$SQL"
        # 删除邮箱目录
        MAILDIR="/var/mail/vhosts/$DOMAIN/$USER"
        rm -rf "$MAILDIR"
        echo "邮箱账户 $EMAIL 已删除（数据库记录和邮箱目录已移除）。"
        ;;
    3)
        echo "----------------------------------------------"
        echo "修改邮箱密码"
        read -p "请输入要修改密码的邮箱地址 (如 user@$DOMAIN): " EMAIL
        USER=${EMAIL%@*}
        DOMAIN_INPUT=${EMAIL#*@}
        if [[ "$DOMAIN_INPUT" != "$DOMAIN" ]]; then
            echo "错误：邮箱域名必须是 $DOMAIN"
            exit 1
        fi
        read -s -p "请输入新密码: " PASS
        echo ""
        ENC_PASS=$(doveadm pw -s SHA512-CRYPT -p "$PASS")
        SQL="UPDATE mailbox SET password = '$ENC_PASS' WHERE user = '$USER' AND domain = '$DOMAIN';"
        execute_sql "$SQL"
        echo "邮箱 $EMAIL 的密码已更新。"
        ;;
    4)
        echo "----------------------------------------------"
        echo "设置全域收件 (Catch-all)"
        read -p "请输入要设置Catch-all的域名 (默认 $DOMAIN): " DM_INPUT
        DM_INPUT=${DM_INPUT:-$DOMAIN}
        if [[ "$DM_INPUT" != "$DOMAIN" ]]; then
            echo "错误：只能为 $DOMAIN 设置 Catch-all"
            exit 1
        fi
        read -p "请输入接收所有邮件的目标邮箱地址 (如 postmaster@$DOMAIN): " TARGET_EMAIL
        TARGET_USER=${TARGET_EMAIL%@*}
        if [[ "$TARGET_EMAIL" != *@* || "${TARGET_EMAIL#*@}" != "$DOMAIN" ]]; then
            echo "错误：邮箱格式不正确或域名不匹配"
            exit 1
        fi
        # 插入 alias 表，如 @domain -> target
        SQL="INSERT INTO alias (address, goto) VALUES ('@$DOMAIN', '$TARGET_EMAIL');"
        execute_sql "$SQL"
        echo "已为域名 $DOMAIN 设置 Catch-all: 所有邮件将投递到 $TARGET_EMAIL"
        ;;
    5)
        echo "----------------------------------------------"
        echo "当前所有邮箱账户列表："
        SQL="SELECT CONCAT(user,'@',domain) AS address FROM mailbox;"
        mysql -h"$DBHOST" -u"$DBUSER" -p"$DBPASS" "$DBNAME" -e "$SQL" -N
        ;;
    *)
        echo "无效选项，脚本结束。"
        ;;
esac
