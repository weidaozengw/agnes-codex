#!/bin/bash
# ============================================================
# agnes-codex-setup.sh
# 一键安装：Claude Code + Agnes API 连通
# 支持平台：macOS、Linux、Windows(WSL2)
# ============================================================

set -e

# ── 颜色定义 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[  OK  ]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ── 检测操作系统 ──
OS_TYPE="unknown"
if [ "$(uname)" = "Darwin" ]; then
    OS_TYPE="macos"
elif [ "$(uname)" = "Linux" ]; then
    # 检测是否在 WSL2 中
    if grep -qi microsoft /proc/version 2>/dev/null; then
        OS_TYPE="windows-wsl"
    else
        OS_TYPE="linux"
    fi
elif [[ "$(uname -s)" = MINGW* ]] || [[ "$(uname -s)" = MSYS* ]]; then
    OS_TYPE="windows-native"
    error "Windows 原生环境不支持，请使用 WSL2 或 Git Bash。"
    exit 1
fi

# 检测架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)   ARCH="x86_64" ;;
    aarch64)  ARCH="aarch64" ;;
    arm64)    ARCH="aarch64" ;;
    *)        error "不支持的架构: $ARCH"; exit 1 ;;
esac

info "检测到操作系统: $OS_TYPE"
info "检测到架构: $ARCH"

# ── 检测 Python ──
PYTHON_CMD=""
for cmd in python3 python; do
    if command -v $cmd &>/dev/null; then
        version=$($cmd --version 2>&1 | grep -oP '(\d+)\.(\d+)')
        major=$(echo $version | cut -d. -f1)
        if [ "$major" -ge 3 ]; then
            PYTHON_CMD=$cmd
            break
        fi
    fi
done

if [ -z "$PYTHON_CMD" ]; then
    error "未找到 Python 3.6+，请先安装 Python。"
    if [ "$OS_TYPE" = "macos" ]; then
        info "运行: brew install python3"
    elif [ "$OS_TYPE" = "linux" ]; then
        info "运行: sudo apt install python3 (Debian/Ubuntu)"
        info "或:   sudo yum install python3 (CentOS/RHEL)"
    fi
    exit 1
fi
ok "Python: $PYTHON_CMD"

# ── 创建安装目录 ──
AGNES_DIR="$HOME/.agnes"
mkdir -p "$AGNES_DIR"

# 代理脚本目录
PROXY_DIR="$AGNES_DIR/bin"
mkdir -p "$PROXY_DIR"

# ── 复制代理脚本 ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp "$SCRIPT_DIR/anthropic_proxy.py" "$PROXY_DIR/anthropic_proxy.py"
ok "代理脚本已安装到: $PROXY_DIR/anthropic_proxy.py"

# ── 用户输入 API Key ──
echo ""
echo "=========================================="
echo "  Agnes AI + Claude Code 一键安装向导"
echo "=========================================="
echo ""
info "请前往 https://platform.agnes-ai.com 注册并获取 API Key"
echo ""
read -rp "请输入你的 Agnes API Key: " API_KEY

if [ -z "$API_KEY" ]; then
    error "API Key 不能为空。"
    exit 1
fi

# 验证格式
if [[ ! "$API_KEY" =~ ^sk- ]]; then
    warn "API Key 格式不以 'sk-' 开头，这可能不是有效的 Key。"
    read -rp "是否继续？(y/n): " continue_input
    if [[ "$continue_input" != "y" && "$continue_input" != "Y" ]]; then
        exit 0
    fi
fi

# 写入 Key（权限 600）
echo "$API_KEY" > "$AGNES_DIR/api-key"
chmod 600 "$AGNES_DIR/api-key"
ok "API Key 已保存到: $AGNES_DIR/api-key (权限 600)"

# ── 检测 Claude Code 是否已安装 ──
CLAUDE_CMD=""
for cmd in claude; do
    if command -v $cmd &>/dev/null; then
        CLAUDE_CMD=$cmd
        break
    fi
done

if [ -z "$CLAUDE_CMD" ]; then
    warn "未检测到 Claude Code。"
    echo ""
    info "请安装 Claude Code："
    if [ "$OS_TYPE" = "macos" ] || [ "$OS_TYPE" = "linux" ]; then
        info "运行: npm install -g @anthropic-ai/claude-code"
    elif [ "$OS_TYPE" = "windows-wsl" ]; then
        info "运行: npm install -g @anthropic-ai/claude-code"
    fi
    echo ""
    read -rp "是否继续配置？(需要先安装 Claude Code) (y/n): " pre_install
    if [[ "$pre_install" != "y" && "$pre_install" != "Y" ]]; then
        error "请先安装 Claude Code 再运行此脚本。"
        exit 1
    fi
    # 重新检测
    for cmd in claude; do
        if command -v $cmd &>/dev/null; then
            CLAUDE_CMD=$cmd
            break
        fi
    done
fi

if [ -z "$CLAUDE_CMD" ]; then
    error "安装后仍未检测到 Claude Code，请检查 npm 全局路径。"
    exit 1
fi

CLAUDE_VERSION=$($CLAUDE_CMD --version 2>/dev/null || echo "unknown")
ok "Claude Code: $CLAUDE_VERSION"

# ── 配置 Claude Code settings.json ──
SETTINGS_DIR="$HOME/.claude"
mkdir -p "$SETTINGS_DIR"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"

if [ -f "$SETTINGS_FILE" ]; then
    info "检测到现有配置: $SETTINGS_FILE"
    info "将更新 ANTHROPIC_BASE_URL 和 ANTHROPIC_AUTH_TOKEN 字段。"
    # 备份
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%Y%m%d%H%M%S)"
fi

# 生成新配置
cat > "$SETTINGS_FILE" << JSONEOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:18765",
    "ANTHROPIC_AUTH_TOKEN": "mock-token-bypass-login",
    "ANTHROPIC_MODEL": "agnes-2.0-flash",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0"
  },
  "enabledPlugins": {},
  "theme": "dark",
  "hasCompletedOnboarding": true,
  "commands": {
    "mcp": true
  }
}
JSONEOF

ok "Claude Code 配置已更新: $SETTINGS_FILE"

# ── 启动代理 ──
info "正在启动 Agnes 代理..."

# 杀掉已存在的代理
kill $(lsof -i :18765 -t 2>/dev/null) 2>/dev/null || true
sleep 1

# 启动代理（后台运行）
nohup $PYTHON_CMD "$PROXY_DIR/anthropic_proxy.py" > "$AGNES_DIR/proxy.log" 2>&1 &
PROXY_PID=$!

# 等待代理启动
sleep 2
if kill -0 $PROXY_PID 2>/dev/null; then
    ok "Agnes 代理已启动 (PID: $PROXY_PID, 端口: 18765)"
else
    error "代理启动失败，查看日志: $AGNES_DIR/proxy.log"
    cat "$AGNES_DIR/proxy.log"
    exit 1
fi

# ── 开机自启动 ──
echo ""
echo "=========================================="
echo "  配置开机自启动"
echo "=========================================="

if [ "$OS_TYPE" = "macos" ]; then
    # macOS: LaunchAgent
    LAUNCHPLIST="$HOME/Library/LaunchAgents/com.agnes.proxy.plist"
    cat > "$LAUNCHPLIST" << PLEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.agnes.proxy</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON_CMD</string>
        <string>$PROXY_DIR/anthropic_proxy.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$AGNES_DIR/proxy.log</string>
    <key>StandardErrorPath</key>
    <string>$AGNES_DIR/proxy-error.log</string>
</dict>
</plist>
PLEOF
    launchctl load "$LAUNCHPLIST" 2>/dev/null || true
    ok "macOS LaunchAgent 已安装: $LAUNCHPLIST"
    info "开机后将自动启动 Agnes 代理"

elif [ "$OS_TYPE" = "linux" ]; then
    # Linux: systemd user service
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"
    SYSTEMD_UNIT="$SYSTEMD_DIR/agnes-proxy.service"

    cat > "$SYSTEMD_UNIT" << SVCEOF
[Unit]
Description=Agnes AI Proxy for Claude Code
After=network.target

[Service]
Type=simple
ExecStart=$PYTHON_CMD $PROXY_DIR/anthropic_proxy.py
Restart=on-failure
StandardOutput=append:$AGNES_DIR/proxy.log
StandardError=append:$AGNES_DIR/proxy-error.log

[Install]
WantedBy=default.target
SVCEOF

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable agnes-proxy.service 2>/dev/null || true
    systemctl --user start agnes-proxy.service 2>/dev/null || true
    ok "systemd 用户服务已安装: $SYSTEMD_UNIT"
    info "启动命令: systemctl --user start agnes-proxy.service"
    info "停止命令: systemctl --user stop agnes-proxy.service"
    info "查看日志: journalctl --user -u agnes-proxy.service -f"

elif [ "$OS_TYPE" = "windows-wsl" ]; then
    # WSL2: 使用 .bashrc 启动
    for profile in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        if [ -f "$profile" ]; then
            echo "" >> "$profile"
            echo "# Agnes Proxy auto-start" >> "$profile"
            echo "nohup $PYTHON_CMD $PROXY_DIR/anthropic_proxy.py > $AGNES_DIR/proxy.log 2>&1 &" >> "$profile"
            break
        fi
    done
    ok "WSL2 开机自启已配置（写入 .bashrc / .zshrc）"
fi

# ── 测试连通性 ──
echo ""
echo "=========================================="
echo "  测试连通性"
echo "=========================================="

# 测试代理
RESPONSE=$(curl -s --max-time 10 http://127.0.0.1:18765/auth 2>&1)
if echo "$RESPONSE" | grep -q "authenticated"; then
    ok "代理响应正常"
else
    warn "代理响应异常: $RESPONSE"
fi

# 测试 Agnes API
info "测试 Agnes API 连通性..."
API_TEST=$(curl -s --max-time 15 -X POST https://apihub.agnes-ai.com/v1/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d '{"model":"agnes-2.0-flash","messages":[{"role":"user","content":"hi"}],"max_tokens":10}' 2>&1)

if echo "$API_TEST" | grep -q "choices"; then
    ok "Agnes API 连通正常"
else
    warn "Agnes API 测试返回: $API_TEST"
    info "这可能是因为 API Key 尚未激活或额度不足，但代理配置已完成。"
fi

# ── 安装完成 ──
echo ""
echo "=========================================="
echo "  安装完成！"
echo "=========================================="
echo ""
echo "  配置文件:"
echo "    代理脚本:     $PROXY_DIR/anthropic_proxy.py"
echo "    API Key:      $AGNES_DIR/api-key (权限 600)"
echo "    Claude 配置:  $SETTINGS_FILE"
echo "    代理日志:     $AGNES_DIR/proxy.log"
echo ""
echo "  使用方式:"
echo "    1. 打开新终端"
echo "    2. 运行: claude"
echo "    3. 直接输入对话内容"
echo ""
echo "  管理代理:"
echo "    启动:     $PYTHON_CMD $PROXY_DIR/anthropic_proxy.py"
echo "    停止:     kill \$(lsof -i :18765 -t)"
echo "    日志:     tail -f $AGNES_DIR/proxy.log"
echo ""
echo "  如需卸载，请手动删除以下文件和目录:"
echo "    rm -rf $AGNES_DIR"
echo "    rm -f $HOME/Library/LaunchAgents/com.agnes.proxy.plist  # macOS"
echo "    rm -f $SETTINGS_FILE"
echo ""
echo "  文档: $SCRIPT_DIR/README.md"
echo ""
