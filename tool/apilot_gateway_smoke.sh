#!/usr/bin/env bash
set -euo pipefail

# 通过 ADB 把手机/模拟器上的 Apilot 网关转发到本机，
# 用 HTTP 请求验证后端链路；整个过程不依赖截图或 IDE。

if ! command -v adb >/dev/null 2>&1; then
  echo "未找到 adb，请先安装 Android SDK platform-tools" >&2
  exit 2
fi
if ! command -v curl >/dev/null 2>&1; then
  echo "未找到 curl，无法执行网关冒烟测试" >&2
  exit 2
fi

serial="${ANDROID_SERIAL:-}"
if [[ -z "$serial" ]]; then
  serial="$(adb devices | awk 'NR > 1 && $2 == "device" {print $1; exit}')"
fi
if [[ -z "$serial" ]]; then
  echo "未发现已连接的 Android 设备或模拟器" >&2
  echo "可先运行：adb devices" >&2
  exit 2
fi

if ! adb -s "$serial" get-state >/dev/null 2>&1; then
  echo "设备不可用：$serial" >&2
  exit 2
fi

gateway_port="${APILOT_GATEWAY_PORT:-8787}"
forward_port="${APILOT_FORWARD_PORT:-18787}"
timeout_seconds="${APILOT_GATEWAY_TIMEOUT:-30}"
run_chat="${APILOT_GATEWAY_SMOKE_CHAT:-0}"
timestamp="$(date +%Y%m%d_%H%M%S)"
out="${1:-build/gateway_smoke/$timestamp}"
mkdir -p "$out"

if ! [[ "$gateway_port" =~ ^[0-9]+$ && "$forward_port" =~ ^[0-9]+$ ]]; then
  echo "端口必须是数字：gateway=$gateway_port forward=$forward_port" >&2
  exit 2
fi

forwarded=0
cleanup() {
  if [[ "$forwarded" == "1" ]]; then
    adb -s "$serial" forward --remove "tcp:$forward_port" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! adb -s "$serial" forward "tcp:$forward_port" "tcp:$gateway_port" >/dev/null; then
  echo "ADB 端口转发失败：本机 tcp:$forward_port 或设备 tcp:$gateway_port 可能已被占用" >&2
  exit 1
fi
forwarded=1

base_url="http://127.0.0.1:$forward_port/v1"
failures=0
checks=()

request_check() {
  local name="$1"
  local method="$2"
  local path="$3"
  local body_file="$out/$name.body"
  local status
  local curl_exit=0
  local -a args=(
    --silent --show-error
    --connect-timeout 5
    --max-time "$timeout_seconds"
    --request "$method"
    --output "$body_file"
    --write-out '%{http_code}'
  )
  if [[ "$method" == "POST" ]]; then
    args+=(
      --header 'Content-Type: application/json'
      --data-binary "@$out/chat.request.json"
    )
  fi
  status="$(curl "${args[@]}" "$base_url$path" 2>"$out/$name.error")" || curl_exit=$?
  if [[ "$curl_exit" != "0" ]]; then
    status="000"
  fi
  printf '%s\n' "$status" > "$out/$name.status"
  checks+=("$name|$status|$body_file")
  if [[ "$status" != 2?? ]]; then
    failures=$((failures + 1))
  fi
}

request_check health GET /health
request_check diagnostics GET /diagnostics
request_check models GET /models

if [[ "$run_chat" == "1" ]]; then
  model="${APILOT_GATEWAY_MODEL:-}"
  if [[ -z "$model" ]]; then
    echo "APILOT_GATEWAY_SMOKE_CHAT=1 时必须提供 APILOT_GATEWAY_MODEL" >&2
    exit 2
  fi
  cat > "$out/chat.request.json" <<JSON
{"model":"$model","messages":[{"role":"user","content":"只回复：网关冒烟测试成功"}],"stream":false,"max_tokens":32}
JSON
  request_check chat POST /chat/completions
fi

summary="$out/summary.json"
{
  echo '{'
  printf '  "serial": "%s",\n' "$serial"
  printf '  "gatewayPort": %s,\n' "$gateway_port"
  printf '  "forwardPort": %s,\n' "$forward_port"
  printf '  "chatRequested": %s,\n' "$([[ "$run_chat" == "1" ]] && echo true || echo false)"
  echo '  "checks": {'
  for index in "${!checks[@]}"; do
    IFS='|' read -r name status body_file <<< "${checks[$index]}"
    comma=','
    if [[ "$index" == "$(( ${#checks[@]} - 1 ))" ]]; then comma=''; fi
    printf '    "%s": {"status": %s, "ok": %s, "bodyFile": "%s", "errorFile": "%s"}%s\n' \
      "$name" "$status" "$([[ "$status" == 2?? ]] && echo true || echo false)" \
      "${body_file#$out/}" "$name.error" "$comma"
  done
  echo '  },'
  printf '  "failedChecks": %s,\n' "$failures"
  printf '  "outputDirectory": "%s"\n' "$out"
  echo '}'
} > "$summary"

cat "$summary"
if [[ "$failures" != "0" ]]; then
  echo "网关冒烟测试失败，响应文件位于：$out" >&2
  for entry in "${checks[@]}"; do
    IFS='|' read -r name status body_file <<< "$entry"
    if [[ "$status" != 2?? ]]; then
      echo "--- $name (HTTP $status) ---" >&2
      cat "$body_file" 2>/dev/null || true
      cat "$out/$name.error" 2>/dev/null || true
      echo >&2
    fi
  done
  exit 1
fi

echo "网关冒烟测试通过：$out"
