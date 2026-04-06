#!/bin/bash
set -euo pipefail

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
log_info() { echo -e "${BLUE}[INFO]${PLAIN} ${1:-}"; }
log_success() { echo -e "${GREEN}[OK]${PLAIN} ${1:-}"; }
log_error() { echo -e "${RED}[ERROR]${PLAIN} ${1:-}"; }
log_warn() { echo -e "${YELLOW}[WARN]${PLAIN} ${1:-}"; }

# 1. Root 权限检查
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "请使用 root 权限运行 (sudo -i)"
        exit 1
    fi
}

# 2. 获取公网网卡 (Dante 需要绑定物理网卡)
get_interface() {
    INTERFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
    if [[ -z "${INTERFACE}" ]]; then
        INTERFACE=$(ip addr 2>/dev/null | awk '/state UP/ {print $2}' | sed 's/://' | head -n 1)
    fi
    log_info "检测到出口网卡: ${GREEN}${INTERFACE}${PLAIN}"
}

# 3. 系统检测与参数设定
check_system() {
    if [[ -f /etc/debian_version ]]; then
        OS="debian"
        CONF_FILE="/etc/danted.conf"
        SERVICE_NAME="danted"
        PM="apt-get"
    elif [[ -f /etc/redhat-release ]]; then
        OS="centos"
        CONF_FILE="/etc/sockd.conf"
        SERVICE_NAME="sockd"
        if command -v dnf >/dev/null 2>&1; then
            PM="dnf"
        else
            PM="yum"
        fi
    else
        log_error "暂不支持该系统，建议使用 Ubuntu/Debian/CentOS"
        exit 1
    fi
}

# 4. 检查是否已安装
check_installed() {
    local is_active=false
    systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null && is_active=true
    if [[ "${is_active}" == "true" ]] || [[ -f "${CONF_FILE}" ]]; then
        echo -e "${YELLOW}检测到 Dante 服务已安装!${PLAIN}"
        echo -e "1. 重新安装/重置密码"
        echo -e "2. 卸载服务"
        read -rp "请选择 [1-2]: " choice
        case "${choice}" in
            1) uninstall_dante "keep_log";;
            2) uninstall_dante; exit 0;;
            *) exit 0;;
        esac
    fi
}

# 5. 卸载逻辑
uninstall_dante() {
    log_info "正在停止并卸载 Dante..."
    systemctl stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
    systemctl disable "${SERVICE_NAME}" >/dev/null 2>&1 || true

    if [[ "${OS}" = "debian" ]]; then
        apt-get purge -y dante-server >/dev/null 2>&1 || true
        apt-get autoremove -y >/dev/null 2>&1 || true
    else
        "${PM}" remove -y dante-server >/dev/null 2>&1 || true
    fi

    rm -f "${CONF_FILE}"

    if [[ -f /etc/dante_user ]] || [[ -f /etc/sockd_user ]]; then
        local old_user=""
        old_user=$(cat /etc/dante_user 2>/dev/null || cat /etc/sockd_user 2>/dev/null || true)
        if [[ -n "${old_user}" ]] && id "${old_user}" &>/dev/null; then
            userdel -r "${old_user}" >/dev/null 2>&1 || true
            rm -f /etc/dante_user /etc/sockd_user
        fi
    fi

    log_success "Dante 已卸载完成"
}

# 6. 安装依赖
install_dependencies() {
    log_info "安装 Dante-server..."
    if [[ "${OS}" = "debian" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y dante-server
    else
        # CentOS/RHEL 需要 EPEL 源
        if [[ "${PM}" = "dnf" ]]; then
            dnf install -y epel-release 2>/dev/null || true
            dnf install -y dante-server 2>/dev/null || dnf install -y dante 2>/dev/null || {
                log_error "Dante 安装失败，请检查软件源"
                exit 1
            }
        else
            yum install -y epel-release 2>/dev/null || true
            yum install -y dante-server 2>/dev/null || yum install -y dante 2>/dev/null || {
                log_error "Dante 安装失败，请检查软件源"
                exit 1
            }
        fi
    fi

    if ! command -v danted >/dev/null 2>&1 && ! command -v sockd >/dev/null 2>&1; then
        log_error "Dante 安装失败，请检查软件源"
        exit 1
    fi
}

# 7. 获取公网IP
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
    # 确保函数返回 0，防止 set -e 误杀
    true
}

# 8. 配置交互
configure_params() {
    clear
    echo -e "################################################"
    echo -e "#   Dante SOCKS5 一键安装脚本 (System Native)  #"
    echo -e "################################################"

    read -rp "请输入端口 (默认 10800): " INPUT_PORT
    PORT="${INPUT_PORT:-10800}"
    if ! [[ "${PORT}" =~ ^[0-9]+$ ]] || [[ "${PORT}" -lt 1 ]] || [[ "${PORT}" -gt 65535 ]]; then
        log_error "端口必须是 1-65535 之间的数字"
        exit 1
    fi
    if ss -tlnp 2>/dev/null | grep -qE ":${PORT}\b" || netstat -tlnp 2>/dev/null | grep -qE ":${PORT}\b"; then
        log_error "端口 ${PORT} 已被占用"
        exit 1
    fi
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
    read -rsp "请输入密码 (默认随机): " INPUT_PASS
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

# 9. 配置系统用户 (Dante 依赖系统 PAM 认证)
setup_user() {
    log_info "正在配置系统代理用户..."

    # 检查用户是否存在，存在则删除重建
    if id "${USER}" &>/dev/null; then
        userdel "${USER}" >/dev/null 2>&1 || true
    fi

    # 创建一个没有 Home 目录、无法 SSH 登录的用户，确保安全
    useradd -r -s /bin/false "${USER}"

    # 设置密码
    echo "${USER}:${PASS}" | chpasswd
    echo "${USER}" > "${CONF_FILE%/*}/dante_user" 2>/dev/null || true
    log_success "用户 ${USER} 已创建 (禁止 SSH 登录)"
}

# 10. 生成配置文件
write_config() {
    log_info "生成配置文件 (${CONF_FILE})..."

    if [[ -z "${INTERFACE}" ]]; then
        log_error "无法检测出口网卡，配置生成失败"
        return 1
    fi

    # 备份旧配置
    [[ -f "${CONF_FILE}" ]] && mv "${CONF_FILE}" "${CONF_FILE}.bak"

    cat > "${CONF_FILE}" <<EOF
logoutput: syslog
user.privileged: root
user.unprivileged: nobody

# 监听端口
internal: 0.0.0.0 port = ${PORT}
# 出口网卡 (自动识别)
external: ${INTERFACE}

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
    systemctl restart "${SERVICE_NAME}"
    systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1

    # 等待启动
    sleep 2

    # 检查状态
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        log_success "Dante 服务启动成功!"
    else
        log_error "Dante 服务启动失败! 请检查端口占用或配置文件"
        journalctl -u "${SERVICE_NAME}" -n 20
        exit 1
    fi

    # 防火墙
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${PORT}"/tcp >/dev/null 2>&1 || true
        ufw allow "${PORT}"/udp >/dev/null 2>&1 || true
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --zone=public --add-port="${PORT}/tcp" --permanent >/dev/null 2>&1 || true
        firewall-cmd --zone=public --add-port="${PORT}/udp" --permanent >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
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
