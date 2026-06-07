#!/usr/bin/env python3
"""
anthropic_proxy.py
Claude Code ↔ Agnes API 双向代理
用途：让 Claude Code 通过 Agnes API 进行对话（无需 Anthropic 账号）
"""
import http.server
import urllib.request
import urllib.error
import json

def get_key():
    """从配置文件读取 Agnes API Key"""
    import os
    for path in [
        os.path.expanduser("~/.agnes/api-key"),
        os.path.expanduser("~/.agnes/api-key.txt"),
        os.path.expanduser("~/.agnes_api_key"),
    ]:
        if os.path.exists(path):
            with open(path) as f:
                return f.read().strip()
    return ""

API_BASE = "https://apihub.agnes-ai.com/v1"

class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        # ── Auth 端点：伪造登录 ──
        if self.path.startswith("/auth"):
            self.send_json(200, {
                "authenticated": True,
                "user": {"email": "user@agnes.ai"},
            })
            return

        # ── 健康检查 ──
        if self.path in ["/health", "/v1/health"]:
            self.send_json(200, {"status": "ok"})
            return

        # ── 模型列表 ──
        if self.path in ["/models", "/v1/models"]:
            self.send_json(200, {
                "object": "list",
                "data": [{"id": "agnes-2.0-flash", "object": "model", "created": 1717700000}],
            })
            return

        # ── 读取请求体 ──
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        data = json.loads(body)

        # ── 清理不兼容字段 ──
        for key in ["tools", "tool_choice", "thinking", "reasoning", "beta"]:
            data.pop(key, None)

        # ── Anthropic 格式 → OpenAI 格式 ──
        is_anthropic = self.path.startswith("/v1/messages")
        if is_anthropic:
            system_content = None
            if "system" in data:
                system_content = data["system"]
                if isinstance(system_content, list) and system_content:
                    system_content = system_content[0].get("content", "")

            messages = []
            for m in data.get("messages", []):
                messages.append({"role": m.get("role", "user"), "content": m.get("content", "")})

            payload = {
                "model": "agnes-2.0-flash",
                "messages": messages,
                "max_tokens": data.get("max_tokens", 4096),
                "stream": False,
            }
            if system_content:
                messages.insert(0, {"role": "system", "content": str(system_content)})
        else:
            payload = data

        # ── 转发到 Agnes ──
        req_data = json.dumps(payload).encode()
        req = urllib.request.Request(
            API_BASE + "/chat/completions",
            data=req_data,
            headers={"Content-Type": "application/json", "Authorization": "Bearer " + get_key()},
        )
        try:
            resp = urllib.request.urlopen(req, timeout=120)
            resp_body = resp.read()
            resp_status = resp.status
        except urllib.error.HTTPError as e:
            resp_body = e.read()
            resp_status = e.code

        # ── 如果是 Anthropic 请求，转回 Anthropic 格式 ──
        if is_anthropic:
            try:
                openai_resp = json.loads(resp_body)
                choice = openai_resp.get("choices", [{}])[0]
                content = choice.get("message", {}).get("content", "")
                if isinstance(content, list):
                    text = "".join(c.get("text", "") for c in content if isinstance(c, dict) and c.get("type") == "text")
                    if not text:
                        text = "I'm here to help!"
                else:
                    text = str(content) if content else ""
                stop_reason = choice.get("finish_reason", "end_turn")
                if stop_reason == "stop":
                    stop_reason = "end_turn"
                resp_data = json.dumps({
                    "type": "message",
                    "role": "assistant",
                    "content": [{"type": "text", "text": text}],
                    "model": openai_resp.get("model", ""),
                    "stop_reason": stop_reason,
                    "stop_sequence": None,
                    "usage": {
                        "input_tokens": openai_resp.get("usage", {}).get("prompt_tokens", 0),
                        "output_tokens": openai_resp.get("usage", {}).get("completion_tokens", 0),
                    },
                }).encode()
            except Exception:
                resp_data = resp_body
        else:
            resp_data = resp_body

        self.send_response(resp_status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(resp_data)

    def do_GET(self):
        if self.path.startswith("/auth") or self.path in ["/health", "/v1/health", "/models", "/v1/models"]:
            self.do_POST()
        else:
            self.send_error(404)

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def log_message(self, format, *args):
        pass

    def send_json(self, status, obj):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(obj).encode())

if __name__ == "__main__":
    port = 18765
    server = http.server.HTTPServer(("127.0.0.1", port), ProxyHandler)
    print(f"Agnes Proxy running on http://127.0.0.1:{port}")
    print(f"Press Ctrl+C to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nProxy stopped.")
        server.server_close()
