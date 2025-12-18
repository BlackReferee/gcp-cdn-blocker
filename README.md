# GCP CDN Egress Blocker

一个专为 Google Cloud Platform (GCP) 设计的自动化防火墙管理工具。它通过抓取 **Cloudflare、Akamai 和 Fastly** 的最新 ASN 路由段，在 GCP VPC 网络层级实施出站拦截，从而规避昂贵的 CDN 互联流量费用。

## 🌟 功能特性
- **云端拦截**：在数据包离开虚拟机前将其丢弃，不计入 CDN 出站流量。
- **动态更新**：自动从 RADB 获取最新的 IP 库，防止因 CDN IP 变动导致的漏洞。
- **一键配置**：交互式安装向导，支持 每天/每周/每月 自动运行。
- **安全检查**：内置自动化测试模块，实时反馈拦截状态。

---

## 🔑 准备工作：配置 GCP 权限

由于脚本需要操作云端防火墙，必须确保你的 VM 实例拥有授权。

### 方式 A：调整实例 API 范围（推荐）
1. 停止你的虚拟机实例。
2. 点击 **“修改 (Edit)”**，找到 **“API 访问范围 (Access Scopes)”**。
3. 选择 **“为每个 API 设置访问权限”**，将 **“计算引擎 (Compute Engine)”** 设为 **“读写 (Read Write)”**。
4. 保存并重新启动。

### 方式 B：IAM 角色授权
在 [GCP IAM 控制台](https://console.cloud.google.com/iam-admin/iam) 找到实例关联的服务账号，为其添加 **`Compute Security Admin`** 角色。



---

## 🛠 安装与使用

### 1. 安装基础依赖
```bash
# Ubuntu / Debian
sudo apt-get update && sudo apt-get install whois -y

# CentOS / RHEL
sudo yum install whois -y
```

### 2. 下载并安装
```bash
curl -O 'https://raw.githubusercontent.com/BlackReferee/gcp-cdn-blocker/main/gcp-cdn-blocker.sh'
chmod +x gcp-cdn-blocker.sh

# 运行交互式向导配置定时更新频率
./gcp-cdn-blocker.sh install
```


---

## 🚀 常用指令命令,描述
|指令|描述|
|---|---|
|./gcp-cdn-blocker.sh update|强制更新：立即抓取新 IP 并同步至 GCP 防火墙|
|./gcp-cdn-blocker.sh check|健康检查：验证 Cloudflare/Fastly/Akamai 的拦截状态|
|./gcp-cdn-blocker.sh clear|完全卸载：清理所有防火墙规则及定时任务|



---

## 🔍 验证拦截效果
运行检测命令后，拦截成功的状态应如下：
```bash
检测目标 1.1.1.1 ... [ 成功拦截 ]
检测目标 151.101.1.69 ... [ 成功拦截 ]
手动测试：curl -I -m 5 https://www.cloudflare.com，应当返回 Connection timed out
```


---

