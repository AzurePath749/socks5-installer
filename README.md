# Easy SOCKS5 Installer

![GitHub release (latest by date)](https://img.shields.io/github/v/release/AzurePath749/socks5-installer?color=blue&style=flat-square)
![License](https://img.shields.io/github/license/AzurePath749/socks5-installer?style=flat-square)
![Shell](https://img.shields.io/badge/language-Shell-orange?style=flat-square)

> 极致轻量、兼容性极强的 SOCKS5 代理一键安装脚本，提供两种内核可选。

---

## 版本对比

| 特性 | Gost 版 (`install_s5.sh`) | Dante 版 (`install_dante.sh`) |
|------|--------------------------|------------------------------|
| 内核 | Gost (Go Simple Tunnel) | Dante (系统原生) |
| 资源占用 | 极低 | 中等 |
| 认证方式 | 内置用户名/密码 | 系统 PAM 认证 |
| 适用场景 | 小内存 VPS、ARM 设备 | 标准 Linux 服务器 |
| 支持平台 | CentOS/Debian/Ubuntu/Alpine/ARM | Debian/Ubuntu/CentOS/RHEL |
| 端口范围 | 自定义或随机 | 自定义或默认 10800 |

---

## Gost 版 (推荐)

采用 **Gost (Go Simple Tunnel)** 作为核心，二进制部署、资源占用极低，完美适配各种"小内存"VPS。

### 核心特性

- **环境自动适配**: 自动检测并补全 `tar`/`gzip` 等基础组件
- **全平台兼容**: CentOS 7+, Ubuntu 16+, Debian 8+, Alpine 以及 ARM 架构
- **交互式配置**: 支持自定义端口、账号密码，或一键生成高强度随机凭证
- **智能守护**: Systemd 服务，开机自启、崩溃重启
- **安全加固**: 低权限用户运行、输入校验、SSL 证书验证、下载完整性校验
- **干净移除**: 完整卸载选项，不残留任何文件

### 快速安装

```bash
# 方式 A：使用 Curl
bash <(curl -sL https://raw.githubusercontent.com/AzurePath749/socks5-installer/main/install_s5.sh)

# 方式 B：使用 wget
bash <(wget -qO- https://raw.githubusercontent.com/AzurePath749/socks5-installer/main/install_s5.sh)
```

### 管理命令

```bash
systemctl start gost    # 启动服务
systemctl stop gost     # 停止服务
systemctl restart gost  # 重启服务
systemctl status gost   # 查看运行状态
```

### 手动卸载

```bash
systemctl stop gost && systemctl disable gost && rm -f /etc/systemd/system/gost.service && rm -f /usr/local/bin/gost && systemctl daemon-reload && echo "卸载完成"
```

---

## Dante 版

采用 **Dante** 作为核心，系统原生 PAM 认证，适合标准 Linux 服务器环境。

### 核心特性

- **系统级认证**: 使用系统用户认证，与系统用户管理集成
- **原生集成**: 通过系统包管理器安装，更新维护方便
- **物理网卡绑定**: 自动检测出口网卡，确保代理流量正确路由
- **安全加固**: 禁止代理用户 SSH 登录、输入校验

### 快速安装

```bash
# 方式 A：使用 Curl
bash <(curl -sL https://raw.githubusercontent.com/AzurePath749/socks5-installer/main/install_dante.sh)

# 方式 B：使用 wget
bash <(wget -qO- https://raw.githubusercontent.com/AzurePath749/socks5-installer/main/install_dante.sh)
```

### 管理命令

```bash
# Debian/Ubuntu
systemctl start danted    # 启动服务
systemctl stop danted     # 停止服务
systemctl restart danted  # 重启服务

# CentOS/RHEL
systemctl start sockd     # 启动服务
systemctl stop sockd      # 停止服务
systemctl restart sockd   # 重启服务
```

### 手动卸载

```bash
# Debian/Ubuntu
systemctl stop danted && systemctl disable danted && apt-get purge -y dante-server && rm -f /etc/danted.conf && echo "卸载完成"

# CentOS/RHEL
systemctl stop sockd && systemctl disable sockd && yum remove -y dante-server && rm -f /etc/sockd.conf && echo "卸载完成"
```

---

## 注意事项

- 安装后如果无法连接，请检查云服务器后台的**安全组**是否放行了对应端口
- 脚本具有幂等性，再次运行可覆盖安装或卸载
- Gost 版运行在低权限 `gost` 用户下，Dante 版代理用户已禁止 SSH 登录
