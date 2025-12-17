#!/bin/bash

# ==================================================
# Project: Easy SOCKS5 Auto-Installer (Gost Version)
# Repo:    https://github.com/AzurePath749/socks5-installer
# Author:  Assistant & AzurePath749
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
        log_error "请使用 root 权限运行此脚本 (sudo -i)"
        exit 1
    fi
}

# 2. 检查是否已安装 (核心逻辑：提供卸载选项)
check_installed() {
    if [ -f "$SERVICE_FILE" ]; then
        clear
        echo -e "################################################"
        echo -e "#   ${YELLOW}检测到 SOCKS5 服务已安装!${PLAIN}                  #"
        echo -e "################################################"
        echo -e "1. 覆盖安装 / 更新配置"
        echo -e "2. 卸载服务 (彻底清除)"
        echo -e "0. 退出脚本"
        echo -e "################################################"
        read -p "请选择 [0-2]: " choice
        case $choice in
            1)
                log_info "准备覆盖安装，先停止旧服务..."
                systemctl stop gost >/dev/null 2>&1
                ;;
            2)
                uninstall_service
                exit 0
                ;;
            *)
                log_info "已退出"
                exit 0
                ;;
        esac
    fi
}

# 3. 卸载函数
uninstall_service() {
    log_info "正在卸载服务..."
    systemctl stop gost >/dev/null 2>&1
    systemctl disable gost >/dev/null 2>&1
    rm -f $SERVICE_FILE
    rm -f $GOST_PATH
    systemctl daemon-reload
    log_success "SOCKS5 服务及文件已卸载完成！"
}

# 4. 系统及架构检测
check_system() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)  GOST_ARCH="linux-amd64";;
        aarch64) GOST_ARCH="linux-armv8";;
        armv7l)  GOST_ARCH="linux-armv7";;
        *)       log_error "不支持的 CPU 架构: $ARCH"; exit 1 ;;
    esac

    if command -v apt-get >/dev/null 2>&1; then PM="apt-get"
    elif command -v yum >/dev/null 2>&1; then PM="yum"
    elif command -v dnf >/dev/null 2>&1; then PM="dnf"
    elif command -v apk >/dev/null 2>&1; then PM="apk"
    else PM="unknown"; fi
}

# 5. 安装依赖
install_dependencies() {
    log_info "检查环境依赖 (如 curl/wget/tar)..."
    [ "$PM" = "unknown" ] && { log_error "无法识别包管理器，请手动安装基础工具"; exit 1; }

    if [ "$PM" = "apk" ]; then
        # Alpine 不需要更新源，直接尝试安装
        $PM add wget curl tar gzip libqrencode >/dev/null 2>&1
    else
        # Debian/CentOS 尝试静默安装
        $PM install -y wget curl tar gzip >/dev/null 2>&1
    fi
    # 二次检查，确保 curl 或 wget 至少有一个
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log_warn "依赖安装可能不完整，尝试强制更新源..."
        if [ "$PM" = "apt-get" ]; then apt-get update -y && apt-get install -y curl wget; fi
        if [ "$PM" = "yum" ]; then yum update -y && yum install -y curl wget; fi
    fi
}

# 6. 获取公网 IP
get_public_ip() {
    # 优先使用 curl，没有则用 wget
    if command -v curl >/dev/null 2>&1; then
        PUBLIC_IP=$(curl -s4 --connect-timeout 5 ip.sb || curl -s4 --connect-timeout 5 ifconfig.me)
    elif command -v wget >/dev/null 2>&1; then
        PUBLIC_IP=$(wget -qO- -T 5 ip.sb || wget -qO- -T 5 ifconfig.me)
    fi

    [ -z "$PUBLIC_IP" ] && PUBLIC_IP="无法获取(请手动查看)"
}

# 7. 用户交互配置
configure_params() {
    clear
    echo -e "################################################"
    echo -e "#   SOCKS5 一键安装脚本 (Gost版)               #"
    echo -e "#   Repo: AzurePath749/socks5-installer        #"
    echo -e "################################################"
    echo ""

    # 端口
    read -p "请输入端口号 (默认随机 10000-65000): " INPUT_PORT
    if [[ -z "$INPUT_PORT" ]]; then
        PORT=$(shuf -i 10000-65000 -n 1)
    elif [[ ! $INPUT_PORT =~ ^[0-9]+$ ]] || [ $INPUT_PORT -lt 1 ] || [ $INPUT_PORT -gt 65535 ]; then
        log_warn "输入无效，使用随机端口"
        PORT=$(shuf -i 10000-65000 -n 1)
    else
        PORT=$INPUT_PORT
    fi

    # 用户名
    read -p "请输入用户名 (默认: admin): " INPUT_USER
    USER=${INPUT_USER:-"admin"}

    # 密码
    read -p "请输入密码 (默认随机强密码): " INPUT_PASS
    if [ -z "$INPUT_PASS" ]; then
        PASS=$(date +%s%N | md5sum | head -c 12)
    else
        PASS=$INPUT_PASS
    fi
}

# 8. 下载并安装 Gost
install_gost() {
    log_info "下载核心组件 (Arch: $GOST_ARCH)..."
    # 如果是覆盖安装，先删除旧文件
    rm -f $GOST_PATH

    URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VER}/gost-${GOST_ARCH}-${GOST_VER}.gz"

    # 优先用 wget 下载，因为它在精简系统更常见
    if command -v wget >/dev/null 2>&1; then
        wget --no-check-certificate -qO /tmp/gost.gz "$URL"
    else
        curl -sL -k -o /tmp/gost.gz "$URL"
    fi

    if [ ! -f "/tmp/gost.gz" ]; then
        log_error "下载失败，请检查服务器网络 (需访问 GitHub)"
        exit 1
    fi

    gzip -d /tmp/gost.gz
    mv /tmp/gost $GOST_PATH
    chmod +x $GOST_PATH
    rm -f /tmp/gost.gz
}

# 9. 配置 Systemd
setup_service() {
    log_info "配置系统服务..."
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=Gost SOCKS5 Proxy
After=network.target

[Service]
Type=simple
User=root
ExecStart=$GOST_PATH -L $USER:$PASS@:$PORT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable gost >/dev/null 2>&1
    systemctl restart gost

    # 等待2秒让服务启动
    sleep 2

    if systemctl is-active --quiet gost; then
        log_success "服务已启动!"
    else
        log_error "服务启动失败，请运行 journalctl -u gost -n 20 查看日志"
        exit 1
    fi
}

# 10. 防火墙
setup_firewall() {
    log_info "尝试配置系统防火墙..."
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
             ufw allow $PORT/tcp >/dev/null 2>&1
             ufw allow $PORT/udp >/dev/null 2>&1
             log_success "已添加 UFW 规则"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state | grep -q "running"; then
            firewall-cmd --zone=public --add-port=$PORT/tcp --permanent >/dev/null 2>&1
            firewall-cmd --zone=public --add-port=$PORT/udp --permanent >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            log_success "已添加 Firewalld 规则"
        fi
    else
        log_warn "未检测到常用防火墙，请手动检查"
    fi
}

# 11. 展示结果
show_result() {
    clear
    echo -e "=================================================="
    echo -e "${GREEN}SUCCESS! 安装完成${PLAIN}"
    echo -e "=================================================="
    echo -e " IP Address : ${GREEN}${PUBLIC_IP}${PLAIN}"
    echo -e " Port       : ${GREEN}${PORT}${PLAIN}"
    echo -e " Username   : ${GREEN}${USER}${PLAIN}"
    echo -e " Password   : ${GREEN}${PASS}${PLAIN}"
    echo -e "=================================================="
    echo -e " SOCKS5 链接 (复制使用):"
    echo -e " ${YELLOW}socks5://${USER}:${PASS}@${PUBLIC_IP}:${PORT}${PLAIN}"
    echo -e "=================================================="
    echo -e "${RED}重要提示:${PLAIN} 如果无法连接，请务必检查："
    echo -e " 1. 云服务器后台(阿里云/AWS等)的【安全组】是否放行了端口 ${PORT}。"
    echo -e " 2. 您的本地网络是否允许连接该服务器 IP。"
    echo -e "=================================================="
}

# --- 主逻辑 ---
main() {
    check_root
    check_system
    # 关键点：在安装前先检查是否已安装
    check_installed
    install_dependencies
    get_public_ip
    configure_params
    install_gost
    setup_service
    setup_firewall
    show_result
}

main
