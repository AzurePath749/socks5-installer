#!/bin/bash
set -e

# ==============================================
# 🧦 Socks5 一键安装脚本（Dante）
# Repo: https://github.com/AzurePath749/socks5-installer
# Author: KenSao
# ==============================================

green="\033[32m"
red="\033[31m"
yellow="\033[33m"
blue="\033[36m"
plain="\033[0m"

echo -e "${blue}🌍 Socks5 (Dante) 一键安装脚本${plain}"
echo -e "${yellow}-------------------------------------${plain}"

# root 权限
if [ "$EUID" -ne 0 ]; then
  echo -e "${red}❌ 请使用 root 用户运行${plain}"
  exit 1
fi

# 安装 dante
if ! command -v danted &>/dev/null; then
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

# 输入参数
read -p "🚪 Socks5 端口 [1080]: " port
port=${port:-1080}

read -p "👤 请输入用户名 [user]: " username
username=${username:-user}

read -p "🔑 请输入密码 [pass123]: " password
password=${password:-pass123}

# 创建用户
if ! id "$username" &>/dev/null; then
  useradd -M -s /usr/sbin/nologin "$username"
fi

echo "$username:$password" | chpasswd

# 获取默认网卡
iface=$(ip route | awk '/default/ {print $5; exit}')

# 写配置
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

# 启动服务
systemctl enable danted
systemctl restart danted

# 输出信息
echo
echo -e "${green}🎉 Socks5 安装完成${plain}"
echo -e "${yellow}-------------------------------------${plain}"
echo -e "🌐 IP      : ${blue}$(hostname -I | awk '{print $1}')${plain}"
echo -e "🚪 端口    : ${blue}$port${plain}"
echo -e "👤 用户名  : ${blue}$username${plain}"
echo -e "🔑 密码    : ${blue}$password${plain}"
echo -e "${yellow}-------------------------------------${plain}"
