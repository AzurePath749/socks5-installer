#!/bin/bash

# ==================================================
# Project: Dante SOCKS5 Auto-Installer (System Native)
# Repo:    https://github.com/AzurePath749/socks5-installer
# Author:  Assistant & AzurePath749
# Filename: install_dante.sh
# ==================================================

# --- 颜色配置 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# --- 变量初始化 ---
CONF_FILE=""
SERVICE_NAME=""
INTERFACE=""

# --- 辅助函数 ---
log_info() { echo -e "${BLUE}[INFO]${PLAIN} $1"; }
log_success() { echo -e "${GREEN}[OK]${PLAIN} $1"; }
log_error() { echo -e "${RED}[ERROR]${PLAIN} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${PLAIN} $1"; }

# 1. Root 权限检查
check_root() {
    [[ $EUID -ne 0 ]] && { log_error "请使用 root 权限运行 (sudo -i)"; exit 1; }
}

# 2. 获取公网网卡 (Dante 需要绑定物理网卡)
get_interface() {
    # 通过访问 8.8.8.8 的路由路径来确定出口网卡
    INTERFACE=$(ip route get 8.8.8.8 | grep -oP 'dev \K\S+')
    if [ -z "$INTERFACE" ]; then
        INTERFACE=$(ip addr | awk '/state UP/ {print $2}' | sed 's/://' | head -n 1)
    fi
    log_info "检测到出口网卡: ${GREEN}$INTERFACE${PLAIN}"
}

# 3. 系统检测与参数设定
check_system() {
    if [ -f /etc/debian_version ]; then
        OS="debian"
        CONF_FILE="/etc/danted.conf"
        SERVICE_NAME="danted"
        PM="apt-get"
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
        CONF_FILE="/etc/sockd.conf"
        SERVICE_NAME="sockd"
        PM="yum"
    else
        log_error "暂不支持该系统，建议使用 Ubuntu/Debian/CentOS"
        exit 1
    fi
}

# 4. 检查是否已安装
check_installed() {
    if systemctl is-active --quiet $SERVICE_NAME || [ -f "$CONF_FILE" ]; then
        echo -e "${YELLOW}检测到 Dante 服务已安装!${PLAIN}"
        echo -e "1. 重新安装/重置密码"
        echo -e "2. 卸载服务"
        read -p "请选择 [1-2]: " choice
        case $choice in
            1) uninstall_dante "keep_log";;
            2) uninstall_dante; exit 0;;
            *) exit 0;;
        esac
    fi
}

# 5. 卸载逻辑
uninstall_dante() {
    log_info "正在停止并卸载 Dante..."
    systemctl stop $SERVICE_NAME >/dev/null 2>&1
    systemctl disable $SERVICE_NAME >/dev/null 2>&1
    
    if [ "$OS" == "debian" ]; then
        apt-get purge -y dante-server >/dev/null 2>&1
        apt-get autoremove -y >/dev/null 2>&1
    else
        yum remove -y dante-server >/dev/null 2>&1
    fi
    
    rm -f $CONF_FILE
    
    # 尝试删除可能创建的代理用户 (如果不清理，下次安装会报错)
    if id "proxy_user" &>/dev/null; then
        userdel -r proxy_user >/dev/null 2>&1
    fi

    log_success "Dante 已卸载完成"
}

# 6. 安装依赖
install_dependencies() {
    log_info "安装 Dante-server..."
    if [ "$OS" == "debian" ]; then
        apt-get update -y
        apt-get install -y dante-server
    else
        # CentOS 需要 EPEL 源
        yum install -y epel-release
        yum install -y dante-server
    fi

    if ! command -v danted >/dev/null 2>&1 && ! command -v sockd >/dev/null 2>&1; then
        log_error "Dante 安装失败，请检查软件源"
        exit 1
    fi
}

# 7. 获取公网IP
get_public_ip() {
    if command -v curl >/dev/null 2>&1; then
        PUBLIC_IP=$(curl -s4 ip.sb)
    else
        PUBLIC_IP=$(wget -qO- ip.sb)
    fi
}

# 8. 配置交互
configure_params() {
    clear
    echo -e "################################################"
    echo -e "#   Dante SOCKS5 一键安装脚本 (System Native)  #"
    echo -e "################################################"
    
    read -p "请输入端口 (默认 10800): " INPUT_PORT
    PORT=${INPUT_PORT:-10800}

    read -p "请输入用户名 (默认: admin): " INPUT_USER
    USER=${INPUT_USER:-"admin"}

    read -p "请输入密码 (默认随机): " INPUT_PASS
    if [ -z "$INPUT_PASS" ]; then
        PASS=$(date +%s%N | md5sum | head -c 12)
    else
        PASS=$INPUT_PASS
    fi
}

# 9. 配置系统用户 (Dante 依赖系统 PAM 认证)
setup_user() {
    log_info "正在配置系统代理用户..."
    
    # 检查用户是否存在，存在则删除重建
    if id "$USER" &>/dev/null; then
        userdel "$USER" >/dev/null 2>&1
    fi

    # 创建一个没有 Home 目录、无法 SSH 登录的用户，确保安全
    useradd -r -s /bin/false "$USER"
    
    # 设置密码
    echo "$USER:$PASS" | chpasswd
    log_success "用户 $USER 已创建 (禁止 SSH 登录)"
}

# 10. 生成配置文件
write_config() {
    log_info "生成配置文件 ($CONF_FILE)..."
    
    # 备份旧配置
    [ -f "$CONF_FILE" ] && mv "$CONF_FILE" "${CONF_FILE}.bak"

    cat > $CONF_FILE <<EOF
logoutput: syslog
user.privileged: root
user.unprivileged: nobody

# 监听端口
internal: 0.0.0.0 port = $PORT
# 出口网卡 (自动识别)
external: $INTERFACE

# 认证方式：系统用户
socksmethod: username
clientmethod: none

user.libwrap: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
EOF
}

# 11. 启动服务与防火墙
start_service() {
    systemctl restart $SERVICE_NAME
    systemctl enable $SERVICE_NAME >/dev/null 2>&1
    
    # 等待启动
    sleep 2
    
    # 检查状态
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_success "Dante 服务启动成功!"
    else
        log_error "Dante 服务启动失败! 请检查端口占用或配置文件"
        journalctl -u $SERVICE_NAME -n 20
        exit 1
    fi

    # 防火墙
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $PORT/tcp >/dev/null 2>&1
        ufw allow $PORT/udp >/dev/null 2>&1
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --zone=public --add-port=$PORT/tcp --permanent >/dev/null 2>&1
        firewall-cmd --zone=public --add-port=$PORT/udp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    fi
}

show_result() {
    clear
    echo -e "=================================================="
    echo -e "${GREEN}Dante (SOCKS5) 安装完成!${PLAIN}"
    echo -e "=================================================="
    echo -e " IP      : ${GREEN}${PUBLIC_IP}${PLAIN}"
    echo -e " Port    : ${GREEN}${PORT}${PLAIN}"
    echo -e " User    : ${GREEN}${USER}${PLAIN}"
    echo -e " Pass    : ${GREEN}${PASS}${PLAIN}"
    echo -e "=================================================="
    echo -e " 链接: ${YELLOW}socks5://${USER}:${PASS}@${PUBLIC_IP}:${PORT}${PLAIN}"
    echo -e "=================================================="
    echo -e " 注意: 这是一个系统级用户，但已禁用了 SSH 登录权限。"
    echo -e "=================================================="
}

main() {
    check_root
    check_system
    check_installed
    get_interface  # 关键步骤
    install_dependencies
    get_public_ip
    configure_params
    setup_user     # 关键步骤
    write_config
    start_service
    show_result
}

main
