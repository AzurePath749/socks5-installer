#!/bin/bash
set -e

green="\033[32m"
red="\033[31m"
yellow="\033[33m"
plain="\033[0m"

echo -e "${yellow}⚠️ 即将卸载 Socks5 (Dante)${plain}"
read -p "确认卸载？[y/N]: " confirm

if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo -e "${yellow}❌ 已取消卸载${plain}"
  exit 0
fi

systemctl stop danted 2>/dev/null || true
systemctl disable danted 2>/dev/null || true

rm -f /etc/danted.conf
rm -f /var/log/danted.log

if [ -f /etc/debian_version ]; then
  apt remove -y dante-server
elif [ -f /etc/redhat-release ]; then
  yum remove -y dante-server
fi

echo -e "${green}✅ Socks5 (Dante) 已完全卸载${plain}"
