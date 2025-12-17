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

# ---------- root 权限 ----------
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

# ---------- 从终端读取输入（关键修复） ----------
echo
read -p "👤 请输入用户名 [user]: " username < /dev/tty
username=${username:-user}

read -p "🔑 请输入密码 [pass123]: " password < /dev/tty
password=${password:-pass123}

read -p "🚪 请输入 Socks5 端口 [1080]: " port < /dev/tty
port=${port:-1080}

# ---------- 校验 ----------
if [[ ! "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
  echo -e "${red}❌ 用户名只能包含字母、数字、下划线${plain}"
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

if [ -z "$iface" ]; then
  echo -e "${red}❌ 无法获取默认网络接口${plain}"
  exit 1
fi

# ---------- 配置 danted ----------
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

# ---------- 启动服务 ----------
systemctl enable danted
systemctl restart danted

# ---------- 输出 ----------
echo
echo -e "${green}🎉 Socks5 安装完成！${plain}"
echo -e "${yellow}-------------------------------------${plain}"
echo -e "🌐 服务器 IP : ${blue}$(hostname -I | awk '{print $1}')${plain}"
echo -e "🚪 端口       : ${blue}$port${plain}"
echo -e "👤 用户名     : ${blue}$username${plain}"
echo -e "🔑 密码       : ${blue}$password${plain}"
echo -e "${yellow}-------------------------------------${plain}"
