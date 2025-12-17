#!/bin/bash
set -e

# ==============================================
# 🧦 Socks5 (Dante) 一键安装脚本
# Repo: https://github.com/AzurePath749/socks5-installer
# ==============================================

green="\033[32m"
red="\033[31m"
yellow="\033[33m"
blue="\033[36m"
plain="\033[0m"

echo -e "${blue}🌍 Socks5 (Dante) 一键安装脚本${plain}"
echo -e "${yellow}-------------------------------------${plain}"

# ---------- root ----------
if [ "$EUID" -ne 0 ]; then
  echo -e "${red}❌ 请使用 root 用户运行${plain}"
  exit 1
fi

# ---------- 安装 dante ----------
if ! command -v danted >/dev/null 2>&1; then
  echo -e "${yellow}📦 正在安装 dante-server...${plain}"
  if [ -f /etc/debian_version ]; then
    apt update -y
    apt install -y dante-server
  elif [ -f /etc/redhat-release ]; then
    yum install -y epel-release
    yum install -y dante-server
  else
    echo -e "${red}❌ 不支持的系统${plain}"
    exit 1
  fi
else
  echo -e "${green}✅ 已安装 dante-server${plain}"
fi

# ---------- 默认参数（关键） ----------
username="user"
password="pass123"
port="1080"

# ---------- 仅在有 TTY 时才交互 ----------
if [ -t 0 ]; then
  echo
  read -p "👤 用户名 [user]: " input
  [ -n "$input" ] && username="$input"

  read -p "🔑 密码 [pass123]: " input
  [ -n "$input" ] && password="$input"

  read -p "🚪 端口 [1080]: " input
  [ -n "$input" ] && port="$input"
fi

# ---------- 校验 ----------
if [[ ! "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
  echo -e "${red}❌ 用户名不合法${plain}"
  exit 1
fi

if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
  echo -e "${red}❌ 端口号不合法${plain}"
  exit 1
fi

# ---------- 创建用户 ----------
if ! id "$username" >/dev/null 2>&1; then
  useradd -M -s /usr/sbin/nologin "$username"
fi
echo "$username:$password" | chpasswd

# ---------- 获取默认网卡 ----------
iface=$(ip route | awk '/default/ {print $5; exit}')
[ -z "$iface" ] && { echo -e "${red}❌ 无法获取网卡${plain}"; exit 1; }

# ---------- 写配置 ----------
cat > /etc/danted.conf <<EOF
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = $port
external: $iface
method: username
user.notprivileged: nobody

client pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
}

socks pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  command: connect bind udpassociate
  socksmethod: username
}
EOF

systemctl enable danted
systemctl restart danted

echo
echo -e "${green}🎉 Socks5 安装完成${plain}"
echo -e "${yellow}-------------------------------------${plain}"
echo -e "🌐 IP      : ${blue}$(hostname -I | awk '{print $1}')${plain}"
echo -e "🚪 端口    : ${blue}$port${plain}"
echo -e "👤 用户名  : ${blue}$username${plain}"
echo -e "🔑 密码    : ${blue}$password${plain}"
echo -e "${yellow}-------------------------------------${plain}"
