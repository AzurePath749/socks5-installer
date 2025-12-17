# 🚀 Easy SOCKS5 Installer (Gost内核版)

![GitHub release (latest by date)](https://img.shields.io/github/v/release/AzurePath749/socks5-installer?color=blue&style=flat-square)
![License](https://img.shields.io/github/license/AzurePath749/socks5-installer?style=flat-square)
![Shell](https://img.shields.io/badge/language-Shell-orange?style=flat-square)

> 一个极致轻量、UI 精美、兼容性极强的 SOCKS5 代理一键安装脚本。

本脚本采用 **Gost (Go Simple Tunnel)** 作为核心，相比传统的 Dante/SS5，它具备**二进制部署、无依赖、内存占用极低**的优势，完美适配各种“小内存”VPS。

---

## ✨ 核心特性

- **⚡️ 零依赖安装**: 自动解决 `curl`/`wget` 缺失问题，开箱即用。
- **🌍 全平台兼容**: 完美支持 CentOS 7+, Ubuntu 16+, Debian 8+, Alpine 以及 **ARM 架构** (树莓派/Oracle Cloud)。
- **🛡️ 交互式配置**: 支持自定义端口、账号密码，也可一键生成高强度随机凭证。
- **⚙️ 智能守护**: 自动配置 Systemd 服务，支持开机自启、崩溃重启。
- **🧹 干净移除**: 提供完整的卸载选项，不残留任何垃圾文件。

---

## 📦 快速安装 (Quick Start)

请根据您的服务器环境，选择以下任意一种方式运行：

### 方式 A：使用 Curl (推荐)
适用于大多数现代 Linux 发行版：
```bash
bash <(curl -sL [https://raw.githubusercontent.com/AzurePath749/socks5-installer/main/install_s5.sh](https://raw.githubusercontent.com/AzurePath749/socks5-installer/main/install_s5.sh))
```
