#!/bin/bash
set -euo pipefail

# ==================================================
# Project: Easy SOCKS5 Auto-Installer (Gost Version)
# Repo:    https://github.com/AzurePath749/socks5-installer
# Author:  Assistant & AzurePath749
# ==================================================

# --- 命令行参数解析 ---
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -p, --port PORT     指定端口号 (默认随机 10000-65000)"
    echo "  -u, --user USER     指定用户名 (默认随机)"
    echo "  -w, --pass PASS     指定密码 (默认随机强密码)"
    echo "  -h, --help          显示帮助信息"
    echo ""
    echo "示例:"
    echo "  $0                      # 交互模式"
    echo "  $0 -p 1080 -u admin -w pass123   # 非交互模式"
    exit 0
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--port) PORT="$2"; shift 2;;
        -u|--user) USER="$2"; shift 2;;
        -w|--pass) PASS="$2"; shift 2;;
        -h|--help) show_help;;
        *) echo "未知参数: $1"; show_help;;
    esac
done

# 如果命令行指定了端口，则跳过交互模式
SKIP_INTERACTIVE=false
[[ -n "${PORT:-}" ]] && SKIP_INTERACTIVE=true

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
TEMP_GOST="/tmp/gost"
TEMP_GOST_GZ="/tmp/gost.gz"

# --- 清理临时文件 ---
trap 'rm -f "${TEMP_GOST}" "${TEMP_GOST_GZ}"' EXIT

# --- 辅助函数 ---
log_info() { echo -e "${BLUE}[INFO]${PLAIN} ${1:-}"; }
log_success() { echo -e "${GREEN}[OK]${PLAIN} ${1:-}"; }
log_error() { echo -e "${RED}[ERROR]${PLAIN} ${1:-}"; }
log_warn() { echo -e "${YELLOW}[WARN]${PLAIN} ${1:-}"; }

# 1. Root 权限检查
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "请使用 root 权限运行此脚本 (sudo -i)"
        exit 1
    fi
}

# 2. 检查是否已安装 (核心逻辑：提供卸载选项)
check_installed() {
    if [[ -f "${SERVICE_FILE}" ]]; then
        clear
        echo -e "################################################"
        echo -e "#   ${YELLOW}检测到 SOCKS5 服务已安装!${PLAIN}                  #"
        echo -e "################################################"
        echo -e "1. 覆盖安装 / 更新配置"
        echo -e "2. 卸载服务 (彻底清除)"
        echo -e "0. 退出脚本"
        echo -e "################################################"
        read -rp "请选择 [0-2]: " choice
        case "${choice}" in
            1)
                log_info "准备覆盖安装，先备份并停止旧服务..."
                cp -f "${SERVICE_FILE}" "${SERVICE_FILE}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
                systemctl stop gost >/dev/null 2>&1 || true
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
    systemctl stop gost >/dev/null 2>&1 || true
    systemctl disable gost >/dev/null 2>&1 || true
    rm -f "${SERVICE_FILE}"
    rm -f "${GOST_PATH}"
    systemctl daemon-reload
    log_success "SOCKS5 服务及文件已卸载完成！"
}

# 4. 系统及架构检测
check_system() {
    ARCH=$(uname -m)
    case "${ARCH}" in
        x86_64)  GOST_ARCH="linux-amd64";;
        aarch64) GOST_ARCH="linux-armv8";;
        armv7l)  GOST_ARCH="linux-armv7";;
        *)       log_error "不支持的 CPU 架构: ${ARCH}"; exit 1 ;;
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
    [[ "${PM}" == "unknown" ]] && { log_error "无法识别包管理器，请手动安装基础工具"; exit 1; }

    if [[ "${PM}" == "apk" ]]; then
        "${PM}" add wget curl tar gzip libqrencode >/dev/null 2>&1 || true
    else
        # 使用 DEBIAN_FRONTEND 避免 debconf 交互问题
        export DEBIAN_FRONTEND=noninteractive
        "${PM}" install -y wget curl tar gzip >/dev/null 2>&1 || true
    fi
    # 二次检查，确保 curl 或 wget 至少有一个
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log_warn "依赖安装可能不完整，尝试强制安装..."
        if [[ "${PM}" == "apt-get" ]]; then apt-get update -y && apt-get install -y curl wget; fi
        if [[ "${PM}" == "yum" ]]; then yum update -y && yum install -y curl wget; fi
        if [[ "${PM}" == "dnf" ]]; then dnf install -y curl wget; fi
    fi
}

# 6. 获取公网 IP
get_public_ip() {
    local ip_services=("ip.sb" "ifconfig.me" "icanhazip.com" "api.ipify.org")
    PUBLIC_IP=""

    for svc in "${ip_services[@]}"; do
        if command -v curl >/dev/null 2>&1; then
            PUBLIC_IP=$(curl -s4 --connect-timeout 5 "${svc}" 2>/dev/null) || true
        elif command -v wget >/dev/null 2>&1; then
            PUBLIC_IP=$(wget -qO- -T 5 "${svc}" 2>/dev/null) || true
        fi
        [[ -n "${PUBLIC_IP}" ]] && break
    done

    [[ -z "${PUBLIC_IP}" ]] && PUBLIC_IP="无法获取(请手动查看)"
    # 确保函数返回 0
    true
}

# 7. 用户交互配置
configure_params() {
    # 如果通过命令行参数传入了所有必要参数，则跳过交互
    if [[ "${SKIP_INTERACTIVE}" == "true" ]] && [[ -n "${PORT:-}" ]] && [[ -n "${USER:-}" ]] && [[ -n "${PASS:-}" ]]; then
        log_info "使用命令行参数配置..."
        # 验证端口
        if [[ ! "${PORT}" =~ ^[0-9]+$ ]] || [[ "${PORT}" -lt 1 ]] || [[ "${PORT}" -gt 65535 ]]; then
            log_error "端口必须是 1-65535 之间的数字"
            exit 1
        fi
        # 验证用户名
        if [[ ! "${USER}" =~ ^[a-zA-Z0-9_]+$ ]]; then
            log_error "用户名只能包含字母、数字和下划线"
            exit 1
        fi
        # 检查端口占用
        if ss -tlnp 2>/dev/null | grep -q ":${PORT} " || netstat -tlnp 2>/dev/null | grep -q ":${PORT} "; then
            log_error "端口 ${PORT} 已被占用"
            exit 1
        fi
        # 确保不会因为 grep 没匹配到而导致 set -e 退出
        true
        log_info "配置完成: 端口=${PORT}, 用户=${USER}"
        return 0
    fi

    # 交互模式（原有逻辑）
    clear
    echo -e "################################################"
    echo -e "#   SOCKS5 一键安装脚本 (Gost版)               #"
    echo -e "#   Repo: AzurePath749/socks5-installer        #"
    echo -e "################################################"
    echo ""

    # 端口
    read -rp "请输入端口号 (默认随机 10000-65000): " INPUT_PORT
    if [[ -z "${INPUT_PORT}" ]]; then
        PORT=$(awk 'BEGIN{srand(); print int(rand()*55001)+10000}')
    elif [[ ! "${INPUT_PORT}" =~ ^[0-9]+$ ]] || [[ "${INPUT_PORT}" -lt 1 ]] || [[ "${INPUT_PORT}" -gt 65535 ]]; then
        log_warn "输入无效，使用随机端口"
        PORT=$(awk 'BEGIN{srand(); print int(rand()*55001)+10000}')
    else
        PORT="${INPUT_PORT}"
    fi

    # 端口占用检测
    if ss -tlnp 2>/dev/null | grep -q ":${PORT} " || netstat -tlnp 2>/dev/null | grep -q ":${PORT} "; then
        log_error "端口 ${PORT} 已被占用，请选择其他端口"
        exit 1
    fi
    # 确保不会因为 grep 没匹配到而导致 set -e 退出
    true

    # 用户名（带输入清洗）
    read -rp "请输入用户名 (默认: admin): " INPUT_USER
    INPUT_USER="${INPUT_USER:-admin}"
    if [[ ! "${INPUT_USER}" =~ ^[a-zA-Z0-9_]+$ ]]; then
        log_error "用户名只能包含字母、数字和下划线 (a-zA-Z0-9_)"
        exit 1
    fi
    USER="${INPUT_USER}"

    # 密码（隐藏输入）
    read -rsp "请输入密码 (默认随机强密码): " INPUT_PASS
    echo ""
    if [[ -z "${INPUT_PASS}" ]]; then
        if command -v openssl >/dev/null 2>&1; then
            PASS=$(openssl rand -hex 12)
        else
            PASS=$(head -c 16 /dev/urandom | xxd -p | head -c 12)
        fi
    else
        PASS="${INPUT_PASS}"
    fi
}

# 8. 下载并安装 Gost
install_gost() {
    log_info "下载核心组件 (Arch: ${GOST_ARCH})..."
    # 覆盖安装前备份旧二进制
    if [[ -f "${GOST_PATH}" ]]; then
        cp -f "${GOST_PATH}" "${GOST_PATH}.bak" 2>/dev/null || true
    fi

    URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VER}/gost-${GOST_ARCH}-${GOST_VER}.gz"

    # 优先用 wget 下载，因为它在精简系统更常见
    if command -v wget >/dev/null 2>&1; then
        wget -qO "${TEMP_GOST_GZ}" "${URL}"
    else
        curl -sL -o "${TEMP_GOST_GZ}" "${URL}"
    fi

    if [[ ! -f "${TEMP_GOST_GZ}" ]]; then
        log_error "下载失败，请检查服务器网络 (需访问 GitHub)"
        exit 1
    fi

    # 校验下载文件完整性 (gzip 格式校验)
    if ! gzip -t "${TEMP_GOST_GZ}" 2>/dev/null; then
        log_error "下载文件损坏 (gzip 校验失败)，请重试"
        exit 1
    fi

    gzip -df "${TEMP_GOST_GZ}"
    mv -f "${TEMP_GOST}" "${GOST_PATH}"
    chmod +x "${GOST_PATH}"
}

# 9. 配置 Systemd
setup_service() {
    log_info "配置系统服务..."

    # 创建低权限用户运行 Gost
    id -u gost &>/dev/null || useradd -r -s /usr/sbin/nologin gost

    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Gost SOCKS5 Proxy
After=network.target

[Service]
Type=simple
User=gost
ExecStart=${GOST_PATH} -L ${USER}:${PASS}@:${PORT}
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
             ufw allow "${PORT}"/tcp >/dev/null 2>&1 || true
             ufw allow "${PORT}"/udp >/dev/null 2>&1 || true
             log_success "已添加 UFW 规则"
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state | grep -q "running"; then
            firewall-cmd --zone=public --add-port="${PORT}/tcp" --permanent >/dev/null 2>&1 || true
            firewall-cmd --zone=public --add-port="${PORT}/udp" --permanent >/dev/null 2>&1 || true
            firewall-cmd --reload >/dev/null 2>&1 || true
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
