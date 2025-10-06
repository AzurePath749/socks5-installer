#!/bin/bash
# ==============================================
# 🌈 一键安装 Socks5 代理服务（Dante）
# 适用系统：Ubuntu / Debian / CentOS / 其他主流 Linux
# 作者：KenSao  / GPT-5 助手
# ==============================================

# ---------- 彩色输出 ----------
green="\033[32m"
red="\033[31m"
yellow="\033[33m"
blue="\033[36m"
plain="\033[0m"

echo -e "${blue}🌍 欢迎使用 Socks5 一键搭建脚本${plain}"
echo -e "${yellow}-------------------------------------${plain}"
echo -e "${green}此脚本将自动安装并配置 dante-server${plain}"
echo

# ---------- 检查 root 权限 ----------
if [ "$EUID" -ne 0 ]; then
  echo -e "${red}❌ 请使用 root 权限运行此脚本！${plain}"
  exit 1
fi

# ---------- 检查并安装 dante ----------
if ! command -v danted &> /dev/null; then
  echo -e "${yellow}📦 未检测到 dante-server，正在安装...${plain}"
  if [ -f /etc/debian_version ]; then
    apt update -y && apt install -y dante-server
  elif [ -f /etc/redhat-release ]; then
    yum install -y epel-release && yum install -y dante-server
  else
    echo -e "${red}❌ 无法识别系统，请手动安装 dante-server${plain}"
    exit 1
  fi
else
  echo -e "${green}✅ 已检测到 dante-server，无需重复安装${plain}"
fi

# ---------- 用户输入 ----------
echo
read -p "🧩 请输入 Socks5 端口（默认1080）: " port
port=${port:-1080}

read -p "👤 请输入用户名（默认 user）: " username
username=${username:-user}

read -p "🔒 请输入密码（默认 pass123）: " password
password=${password:-pass123}

# ---------- 创建用户 ----------
if ! id "$username" &>/dev/null; then
  useradd -M -s /usr/sbin/nologin "$username"
fi
echo "$username:$password" | chpasswd
echo -e "${green}✅ 已创建认证用户：${username}${plain}"

# ---------- 配置文件 ----------
cat > /etc/danted.conf <<EOF
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = $port
external: $(ip route get 1 | awk '{print $7;exit}')
method: username none
user.notprivileged: nobody

client pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: connect disconnect
}

socks pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  command: connect bind udpassociate
  log: connect disconnect
  socksmethod: username
}
EOF

# ---------- 启动服务 ----------
systemctl enable danted
systemctl restart danted

# ---------- 显示结果 ----------
echo
echo -e "${green}🎉 Socks5 代理安装完成！${plain}"
echo -e "${yellow}-------------------------------------${plain}"
echo -e "🌐 服务器IP：${blue}$(hostname -I | awk '{print $1}')${plain}"
echo -e "🚪 端口：${blue}$port${plain}"
echo -e "👤 用户名：${blue}$username${plain}"
echo -e "🔑 密码：${blue}$password${plain}"
echo -e "${yellow}-------------------------------------${plain}"
echo -e "${green}✅ 您可以使用以上信息连接 Socks5 代理${plain}"
echo -e "${blue}（例如在 Clash、Shadowsocks、浏览器中设置）${plain}"
echo
