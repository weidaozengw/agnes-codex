# Claude Code + Agnes AI Proxy

<p align="center">
  让 Claude Code 通过 Agnes AI 进行对话，无需 Anthropic 账号。
</p>

## 功能特性

- 零成本：使用 Agnes AI 免费 API，无需 Anthropic 付费账号
- 一键安装：运行一个脚本，自动完成全部配置
- 跨平台：支持 macOS、Linux、Windows(WSL2)
- 开机自启：代理自动启动，无需手动管理

## 前置条件

- Python 3.6+
- Claude Code 已安装（`npm install -g @anthropic-ai/claude-code`）
- Agnes API Key（从 [platform.agnes-ai.com](https://platform.agnes-ai.com) 注册获取）

## 快速开始

```bash
curl -L https://raw.githubusercontent.com/USER/REPO/main/agnes-codex-setup.sh | bash
```

## 项目结构

```
agnes-proxy/
├── agnes-codex-setup.sh   # 一键安装脚本
├── anthropic_proxy.py     # 协议转换代理
└── README.md              # 本文件
```

## 安装后配置

```bash
# 启动代理
python3 anthropic_proxy.py

# 或配置开机自启（见下方各平台说明）
```

## 原理说明

Claude Code 使用 Anthropic 协议，Agnes AI 提供 OpenAI 兼容接口。
代理做三层转换：

1. **协议转换**：Anthropic ↔ OpenAI
2. **登录绕过**：拦截 `/auth` 端点，返回伪造的登录成功状态
3. **格式适配**：过滤 Anthropic 独有字段（tools、beta 等）

## 管理代理

```bash
# 启动
python3 ~/.agnes/bin/anthropic_proxy.py

# 停止
kill $(lsof -i :18765 -t)

# 查看日志
tail -f ~/.agnes/proxy.log
```

## 卸载

```bash
rm -rf ~/.agnes
```

## 常见问题

**Claude Code 提示 Not logged in**
确保代理正在运行。代理会自动绕过登录检查。

**端口 18765 被占用**
编辑 `anthropic_proxy.py` 末尾的 `port = 18765` 改为其他端口。

**API Key 无效**
确认 Key 从 platform.agnes-ai.com 获取，格式以 `sk-` 开头。

## 许可

MIT License
