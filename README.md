 🧰 超级工具箱 一键安装脚本

本项目支持 HY2 + VLESS 节点的快速部署和管理，适用于 Ubuntu 22.04 系统。

---

## 🛠️ 安装方法（建议一键命令）

```bash
apt update && apt install -y curl && curl -sL https://raw.githubusercontent.com/VSWSV/VPN/main/install.sh -o install.sh && bash install.sh

```

---

## 📚 使用步骤

1️⃣ **一键安装组件**
- 启动主菜单后，选择 `❶ 安装-升级` → `❶ 全新安装`，自动安装 sing-box、Cloudflare 隧道、依赖项等。

2️⃣ **配置节点信息**
- 返回主菜单，选择 `❹ 配置-节点`，根据提示填写 HY2 或 VLESS 配置，包括端口、UUID、SNI 等。

3️⃣ **启动服务**
- 返回主菜单，选择 `❷ 启动-服务` → 启动 HY2/VLESS 节点。
- 启动成功后，系统将自动弹出你的订阅链接供你复制使用。

---

## 🎁 功能亮点

- 支持 HY2/VLESS 双协议
- 自动生成订阅链接
- 一键更新升级
- 节点缓存清理、日志管理、测速工具
- 完整卸载与依赖修复
