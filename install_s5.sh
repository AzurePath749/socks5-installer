#!/bin/bash

# ==================================================
# Project: Easy SOCKS5 Auto-Installer based on Gost
# System:  Linux (Debian/Ubuntu/CentOS/Fedora)
# Author:  Assistant
# ==================================================

# --- 颜色配置 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PLAIN='\033[0m'

# --- 基础变量 ---
GOST_VER="2.11.5"
GOST_PATH="/usr/local/bin/gost"
SERVICE_FILE="/etc/systemd/system/gost.service"

# --- 辅助函数 ---
log_info() { echo -e "${BLUE}[INFO]${PLAIN} $1"; }
log_success() { echo -e "${GREEN}[OK]${PLAIN} $1"; }
log_error() { echo -e "${RED}[ERROR]${PLAIN} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${PLAIN} $1"; }

# 1. Root 权限检查
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行此脚本 (Please run as root)"
        exit 1
    fi
}

# 2. 系统及架构检测
check_system() {
    log_info "正在检测系统环境..."
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  GOST_ARCH="linux-amd64";;
        aarch64) GOST_ARCH="linux-armv8";;
        armv7l)  GOST_ARCH="linux-armv7";;
        *)       log_error "不支持的 CPU 架构: $ARCH"; exit 1 ;;
    esac
    log_success "检测到架构: $ARCH ($GOST_ARCH)"

    # 检测包管理器
    if command -v apt-get >/dev/null 2>&1; then
        PM="apt-get"
    elif command -v yum >/dev/null 2>&1; then
        PM="yum"
    elif command -v dnf >/dev/null 2>&1; then
        PM="dnf"
    elif command -v apk >/dev/null 2>&1; then
        PM="apk" 
    else
        log_error "无法识别包管理器，请手动安装 wget 和 tar"
        exit 1
    fi
}

# 3. 安装依赖
install_dependencies() {
    log_info "正在安装必要依赖..."
    if [ "$PM" = "apk" ]; then
        $PM add wget curl tar gzip >/dev/null 2>&1
    else
        $PM install -y wget curl tar gzip >/dev/null 2>&1
    fi
    log_success "依赖安装完成"
}

# 4. 获取公网 IP
get_public_ip() {
    log_info "正在获取公网 IP..."
    PUBLIC_IP=$(curl -s4 --connect-timeout 5 ip.sb || curl -s4 --connect-timeout 5 ifconfig.me)
    if [ -z "$PUBLIC_IP" ]; then
        PUBLIC_IP="无法获取 (Unknown)"
        log_warn "自动获取 IP 失败，请稍后手动确认"
    else
        log_success "当前公网 IP: $PUBLIC_IP"
    fi
}

# 5. 用户交互配置
configure_params() {
    echo -e "------------------------------------------------"
    echo -e "${YELLOW}请配置 SOCKS5 代理参数 (直接回车使用默认值)${PLAIN}"
    echo -e "------------------------------------------------"

    # 端口配置
    read -p "请输入端口号 (默认随机 10000-65000): " INPUT_PORT
    if [ -z "$INPUT_PORT" ]; then
        PORT=$(shuf -i 10000-65000 -n 1)
    else
        if [[ ! $INPUT_PORT =~ ^[0-9]+$ ]] || [ $INPUT_PORT -lt 1 ] || [ $INPUT_PORT -gt 65535 ]; then
            log_error "端口无效，使用随机端口"
            PORT=$(shuf -i 10000-65000 -n 1)
        else
            PORT=$INPUT_PORT
        fi
    fi

    # 用户名配置
    read -p "请输入用户名 (默认: admin): " INPUT_USER
    USER=${INPUT_USER:-"admin"}

    # 密码配置
    read -p "请输入密码 (默认随机生成): " INPUT_PASS
    if [ -z "$INPUT_PASS" ]; then
        PASS=$(date +%s%N | md5sum | head -c 12)
    else
        PASS=$INPUT_PASS
    fi

    echo -e "------------------------------------------------"
    log_info "配置已确认: Port=$PORT, User=$USER"
}

# 6. 下载并安装 Gost
install_gost() {
    # 停止旧服务
    systemctl stop gost >/dev/null 2>&1

    log_info "正在下载 Gost v${GOST_VER}..."
    URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VER}/gost-${GOST_ARCH}-${GOST_VER}.gz"
    
    wget --no-check-certificate -O /tmp/gost.gz "$URL"
    if [ $? -ne 0 ]; then
        log_error "下载失败，请检查网络连接或 GitHub 访问情况"
        exit 1
    fi

    log_info "正在安装..."
    gzip -d /tmp/gost.gz
    mv /tmp/gost $GOST_PATH
    chmod +x $GOST_PATH
    rm -f /tmp/gost.gz
    log_success "Gost 安装成功"
}

# 7. 配置 Systemd 服务
setup_service() {
    log_info "配置开机自启..."
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=Gost SOCKS5 Proxy Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=$GOST_PATH -L $USER:$PASS@:$PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable gost >/dev/null 2>&1
    systemctl start gost
    
    # 检查状态
    if systemctl is-active --quiet gost; then
        log_success "服务启动成功"
    else
        log_error "服务启动失败，请检查日志 (journalctl -u gost)"
        exit 1
    fi
}

# 8. 防火墙配置 (尽力而为)
setup_firewall() {
    log_info "尝试配置防火墙放行端口 $PORT..."
    if command -v ufw >/dev/null 2>&1; then
        ufw allow $PORT/tcp >/dev/null 2>&1
        ufw allow $PORT/udp >/dev/null 2>&1
        log_success "UFW 防火墙规则已添加"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --zone=public --add-port=$PORT/tcp --permanent >/dev/null 2>&1
        firewall-cmd --zone=public --add-port=$PORT/udp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
        log_success "Firewalld 防火墙规则已添加"
    else
        log_warn "未检测到 UFW 或 Firewalld，请手动检查防火墙设置"
    fi
}

# 9. 显示结果
show_result() {
    clear
    echo -e "=================================================="
    echo -e "${GREEN}          SOCKS5 代理安装完成!            ${PLAIN}"
    echo -e "=================================================="
    echo -e " IP 地址    : ${GREEN}${PUBLIC_IP}${PLAIN}"
    echo -e " 端口 (Port): ${GREEN}${PORT}${PLAIN}"
    echo -e " 用户 (User): ${GREEN}${USER}${PLAIN}"
    echo -e " 密码 (Pass): ${GREEN}${PASS}${PLAIN}"
    echo -e "=================================================="
    echo -e " 连接字符串 (可以直接复制使用):"
    echo -e "${YELLOW}socks5://${USER}:${PASS}@${PUBLIC_IP}:${PORT}${PLAIN}"
    echo -e "=================================================="
    echo -e "${RED}[重要提示]${PLAIN} 如果无法连接，请务必检查："
    echo -e " 1. 云服务商控制台(阿里云/腾讯云/AWS)的【安全组】是否放行了端口 ${PORT}。"
    echo -e " 2. 本地电脑的网络环境是否允许连接该服务器 IP。"
    echo -e "=================================================="
}

# --- 主逻辑执行 ---
main() {
    clear
    echo -e "${BLUE}>>> 开始安装 Easy SOCKS5 (Gost版)...${PLAIN}"
    check_root
    check_system
    install_dependencies
    get_public_ip
    configure_params
    install_gost
    setup_service
    setup_firewall
    show_result
}

main
