#!/usr/bin/env bash
set -uo pipefail

# Apilot 统一验证入口：默认只跑后端可重复验证；连接 Android 设备后自动追加
# 设备诊断。不会强制依赖截图、IDE 或真实云端 Key。

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

timestamp="$(date +%Y%m%d_%H%M%S)"
out="${APILOT_VERIFY_OUTPUT:-build/apilot_verify/$timestamp}"
mkdir -p "$out"

build_kind="${APILOT_BUILD_APK:-none}"
require_device="${APILOT_REQUIRE_DEVICE:-0}"
run_device_diagnostics="${APILOT_DEVICE_DIAGNOSTICS:-1}"
run_gateway_smoke="${APILOT_RUN_GATEWAY_SMOKE:-0}"

step_names=()
step_statuses=()
step_logs=()
failures=0

run_step() {
  local name="$1"
  shift
  local log="$out/$name.log"
  step_names+=("$name")
  step_logs+=("${log#$out/}")
  echo "==> $name"
  if "$@" >"$log" 2>&1; then
    step_statuses+=("passed")
    echo "通过：$name"
  else
    step_statuses+=("failed")
    failures=$((failures + 1))
    echo "失败：${name}（详见 ${log}）" >&2
  fi
}

skip_step() {
  local name="$1"
  local reason="$2"
  step_names+=("$name")
  step_statuses+=("skipped")
  step_logs+=("$reason")
  echo "跳过：${name}（${reason}）"
}

run_step quality_gate env APILOT_SKIP_ANDROID_BUILD=1 tool/run_quality_gate.sh

case "$build_kind" in
  none|0|"")
    skip_step android_build 'APILOT_BUILD_APK 未设置'
    ;;
  debug|release)
    run_step "android_build_$build_kind" flutter build apk "--$build_kind"
    ;;
  *)
    echo "APILOT_BUILD_APK 只支持 none、debug 或 release" >&2
    failures=$((failures + 1))
    skip_step android_build '配置值无效'
    ;;
esac

serial="${ANDROID_SERIAL:-}"
if command -v adb >/dev/null 2>&1 && [[ -z "$serial" ]]; then
  serial="$(adb devices | awk 'NR > 1 && $2 == "device" {print $1; exit}')"
fi

if [[ -z "$serial" ]]; then
  if [[ "$require_device" == "1" ]]; then
    failures=$((failures + 1))
    skip_step device_diagnostics '未发现 Android 设备（APILOT_REQUIRE_DEVICE=1）'
    [[ "$run_gateway_smoke" == "1" ]] && skip_step gateway_smoke '未发现 Android 设备'
  else
    skip_step device_diagnostics '未发现 Android 设备，后端验证仍可完成'
    [[ "$run_gateway_smoke" == "1" ]] && skip_step gateway_smoke '未发现 Android 设备'
  fi
else
  if [[ "$run_device_diagnostics" == "1" ]]; then
    run_step device_diagnostics env ANDROID_SERIAL="$serial" \
      tool/apilot_device_diagnostics.sh "$out/device_diagnostics"
  else
    skip_step device_diagnostics 'APILOT_DEVICE_DIAGNOSTICS=0'
  fi
  if [[ "$run_gateway_smoke" == "1" ]]; then
    run_step gateway_smoke env ANDROID_SERIAL="$serial" \
      tool/apilot_gateway_smoke.sh "$out/gateway_smoke"
  else
    skip_step gateway_smoke 'APILOT_RUN_GATEWAY_SMOKE=1 才执行'
  fi
fi

summary="$out/summary.json"
{
  echo '{'
  printf '  "outputDirectory": "%s",\n' "$out"
  printf '  "androidSerial": "%s",\n' "$serial"
  printf '  "failedSteps": %s,\n' "$failures"
  echo '  "steps": {'
  for index in "${!step_names[@]}"; do
    comma=','
    if [[ "$index" == "$(( ${#step_names[@]} - 1 ))" ]]; then comma=''; fi
    printf '    "%s": {"status": "%s", "log": "%s"}%s\n' \
      "${step_names[$index]}" "${step_statuses[$index]}" \
      "${step_logs[$index]}" "$comma"
  done
  echo '  }'
  echo '}'
} > "$summary"

cat "$summary"
if [[ "$failures" != "0" ]]; then
  echo "统一验证失败，完整日志位于：$out" >&2
  exit 1
fi
echo "统一验证完成：$out"
