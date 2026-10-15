# 校园网自动登录与重连（Windows / Dr.COM）

检测校园网认证状态，在认证失效后使用本机保存的账号密码重新登录。当前适配的登录页为 `http://10.10.102.50/`；其他学校即使使用 Dr.COM，也可能需要修改接口与认证方式。

## 使用

1. 下载仓库 ZIP 并解压到固定文件夹，或克隆仓库。
2. 双击 `首次配置.cmd`，在本机输入账号、运营商和密码。
3. 双击 `启动自动重连.cmd`，保持窗口运行。
4. 可选：双击 `设为开机启动.cmd`，以后登录 Windows 后在后台运行。

支持 Windows 自带的 Windows PowerShell 5.1，无需额外依赖或管理员权限。完整操作和 VPN 使用说明见 [使用说明.md](使用说明.md)。

## 行为

- 每 5 秒查询登录页自己的认证接口，首次确认未登录后立即使用已保存的账号密码提交登录。
- 监听网络地址、连接可用性和电脑唤醒事件，变化后立即复查并重新建立认证连接；事件不可用时仍有定时查询和网卡变化检测。
- 查询失败、Wi-Fi 未恢复或状态不明确时等待，不据此提交密码。
- 区分未连接、IPv4 未就绪、地址变化、接口超时、拒绝连接、权限限制、服务器错误和协议变化，日志附带原因代码、接口阶段和处理建议。
- 登录失败后逐步延长等待时间；明确的账号密码或验证码错误会停止自动提交。
- 绕过系统 HTTP 代理；VPN 的 TUN 路由仍需允许认证服务器直连。
- 密码以 Windows DPAPI 加密保存在 `data/credential.xml`，账号在该文件中为普通文本。运行日志不记录账号、密码或认证请求网址。
- 双击 `检查账号记录.cmd` 可验证本机账号记录；修改配置后，下次重登会读取最新保存的账号密码。

`data/` 已通过 `.gitignore` 排除，请勿将其手动上传到 GitHub。学校接口使用 HTTP，本机的密码加密保存不会改变认证请求的传输方式。

## 网络诊断

双击 `检查连接.cmd` 查看认证结果和处理建议；双击 `诊断网络.cmd` 还会显示 VPN 隧道是否启用，以及认证地址的 TCP 端口 80、801 是否可达。两种检查都不会提交登录密码或修改网络设置。

例如 `[RequestTimeout/PortalConfig]` 表示获取认证配置时超时，`[ServerError/SessionList/HTTP 503]` 表示查询会话时收到服务器错误。检测到 VPN 仅作为排查线索，不会直接断定 VPN 拦截。详细分类见 [使用说明.md](使用说明.md)。

## 验证

在 Windows PowerShell 中运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-CampusNetwork.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-CampusDiagnostics.ps1
```

测试使用虚拟凭据、模拟接口响应和模拟事件，不向校园网发送真实登录请求，也不切换 Wi-Fi 或休眠电脑。涵盖立即重连、重试间隔、DPAPI、故障分类、日志脱敏、网络变化和唤醒响应。真实断线后的登录恢复需要在目标校园网中完成配置后验证。

## 文件

| 文件 | 用途 |
| --- | --- |
| `CampusNetwork.ps1` | 配置、监测、停止和开机启动入口 |
| `CampusNetwork.Core.ps1` | 状态查询、认证请求和重试逻辑 |
| `CampusNetwork.Diagnostics.ps1` | 本机连接判断、故障分类、端口探测和事件监听 |
| `Test-CampusNetwork.ps1` | 无需校园网连接的模拟测试 |
| `Test-CampusDiagnostics.ps1` | 故障响应和系统事件测试 |
| `*.cmd` | 可双击的操作入口 |

工具不能更改学校认证有效期，也不能代替 Wi-Fi 连接恢复、缴费或验证码操作。
