#!/bin/bash
# 邮箱账户管理脚本
# 支持创建、删除、修改密码、设置 Catch-All、列出账户
# 交互式中文界面，提示美化

# 终端颜色定义
GREEN="\033[1;32m"
BLUE="\033[1;34m"
RED="\033[1;31m"
NC="\033[0m"
info()    { echo -e "${BLUE}==> $1${NC}"; }
success() { echo -e "${GREEN}==> $1${NC}"; }
error()   { echo -e "${RED}==> $1${NC}"; }

echo "============================= 邮箱账户管理脚本 ============================="
# 数据库连接信息
read -p "请输入 MariaDB 数据库名: " dbname
read -p "请输入 MariaDB 用户名: " dbuser
echo -n "请输入 MariaDB 用户密码: "
read -s dbpass
echo
# 测试数据库连接
mysql -u$dbuser -p$dbpass -e "use $dbname;" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    error "无法连接到数据库，请检查用户名和密码。"
    exit 1
fi

while true; do
    echo
    echo "请选择操作："
    echo " 1) 创建邮箱账户"
    echo " 2) 删除邮箱账户"
    echo " 3) 修改邮箱密码"
    echo " 4) 设置 Catch-All (全域邮箱转发)"
    echo " 5) 列出所有邮箱账户"
    echo " 6) 退出"
    read -p "请输入选项[1-6]: " choice
    case $choice in
        1)
            # 创建账户
            echo
            info "可用域名："
            mysql -u$dbuser -p$dbpass $dbname -e "SELECT name FROM domain WHERE active=1;"
            read -p "请输入邮箱域名: " dom
            did=$(mysql -u$dbuser -p$dbpass -N -s $dbname -e "SELECT id FROM domain WHERE name='$dom' AND active=1;")
            if [ -z "$did" ]; then
                error "域名不存在，请先配置域名。"
                continue
            fi
            read -p "请输入邮箱用户名（不含域名）: " user
            read -p "请输入用户名 (备注): " name
            echo -n "请输入密码: "
            read -s pass
            echo
            # 生成加密密码
            encpass=$(doveadm pw -s MD5-CRYPT -p "$pass")
            maildir="${dom}/${user}/"
            info "正在创建邮箱账号 ${user}@${dom} ..."
            mysql -u$dbuser -p$dbpass $dbname -e "INSERT INTO mailbox (domain_id, username, password, name, maildir) VALUES ($did, '$user', '$encpass', '$name', '$maildir');"
            sudo mkdir -p /var/mail/vhosts/$dom/$user
            sudo chown vmail:vmail /var/mail/vhosts/$dom/$user
            success "邮箱账户 ${user}@${dom} 创建完成。"
            ;;
        2)
            # 删除账户
            echo
            read -p "请输入要删除的邮箱地址 (例如 user@example.com): " addr
            IFS='@' read -r user dom <<< "$addr"
            if [ -z "$user" ] || [ -z "$dom" ]; then
                error "邮箱地址格式不正确。"
                continue
            fi
            id=$(mysql -u$dbuser -p$dbpass -N -s $dbname -e "SELECT m.id FROM mailbox m JOIN domain d ON m.domain_id=d.id WHERE d.name='$dom' AND m.username='$user';")
            if [ -z "$id" ]; then
                error "未找到邮箱账户 ${addr}。"
                continue
            fi
            read -p "确认删除邮箱 ${addr} 及其邮件数据？(Y/N): " confirm
            if [[ $confirm =~ ^[Yy] ]]; then
                mysql -u$dbuser -p$dbpass $dbname -e "DELETE FROM mailbox WHERE id=$id;"
                sudo rm -rf /var/mail/vhosts/$dom/$user
                success "邮箱 ${addr} 已删除。"
            else
                info "取消删除 ${addr}。"
            fi
            ;;
        3)
            # 修改密码
            echo
            read -p "请输入要修改密码的邮箱地址 (例如 user@example.com): " addr
            IFS='@' read -r user dom <<< "$addr"
            if [ -z "$user" ] || [ -z "$dom" ]; then
                error "邮箱地址格式不正确。"
                continue
            fi
            id=$(mysql -u$dbuser -p$dbpass -N -s $dbname -e "SELECT m.id FROM mailbox m JOIN domain d ON m.domain_id=d.id WHERE d.name='$dom' AND m.username='$user';")
            if [ -z "$id" ]; then
                error "未找到邮箱账户 ${addr}。"
                continue
            fi
            echo -n "请输入新密码: "
            read -s newpass
            echo
            encpass=$(doveadm pw -s MD5-CRYPT -p "$newpass")
            mysql -u$dbuser -p$dbpass $dbname -e "UPDATE mailbox SET password='$encpass' WHERE id=$id;"
            success "邮箱 ${addr} 密码已更新。"
            ;;
        4)
            # 设置 Catch-All
            echo
            info "可用域名："
            mysql -u$dbuser -p$dbpass $dbname -e "SELECT name FROM domain WHERE active=1;"
            read -p "请输入要设置 Catch-All 的域名: " dom
            did=$(mysql -u$dbuser -p$dbpass -N -s $dbname -e "SELECT id FROM domain WHERE name='$dom' AND active=1;")
            if [ -z "$did" ]; then
                error "域名不存在。"
                continue
            fi
            read -p "请输入 Catch-All 转发目标邮箱 (例如 user@example.com): " target
            # 设置 Postfix luser_relay
            sudo postconf -e "luser_relay = $target"
            success "已将未匹配的邮件转发到 ${target}。"
            ;;
        5)
            # 列出账户
            echo
            info "当前邮箱账户列表："
            mysql -u$dbuser -p$dbpass $dbname -e "SELECT CONCAT(m.username,'@',d.name) AS 邮箱, m.name AS 用户名 FROM mailbox m JOIN domain d ON m.domain_id=d.id WHERE m.active=1;"
            ;;
        6)
            info "退出脚本。"
            exit 0
            ;;
        *)
            error "无效选项，请输入数字 1-6。"
            ;;
    esac
done
