#!/usr/bin/env bash
set -euo pipefail

serial="${ANDROID_SERIAL:-}"
if [[ -z "$serial" ]]; then
  serial="$(adb devices | awk 'NR > 1 && $2 == "device" {print $1; exit}')"
fi
if [[ -z "$serial" ]]; then
  echo "未发现已连接的 Android 设备" >&2
  exit 1
fi

package="${APILOT_ANDROID_PACKAGE:-com.example.api_manager}"
timestamp="$(date +%Y%m%d_%H%M%S)"
out="${1:-build/device_diagnostics/$timestamp}"
mkdir -p "$out"

adb_cmd() { adb -s "$serial" "$@"; }

adb_cmd shell getprop > "$out/getprop.txt"
adb_cmd shell dumpsys activity activities > "$out/activity.txt"
adb_cmd shell dumpsys meminfo "$package" > "$out/meminfo.txt" || true
adb_cmd shell dumpsys gfxinfo "$package" > "$out/gfxinfo.txt" || true
adb_cmd shell dumpsys package "$package" > "$out/package.txt" || true
adb_cmd logcat -d -t 12000 > "$out/logcat.txt"

version_name="$(sed -n 's/.*versionName=\([^ ]*\).*/\1/p' "$out/package.txt" | head -n 1)"
version_code="$(sed -n 's/.*versionCode=\([^ ]*\).*/\1/p' "$out/package.txt" | head -n 1)"
foreground="$(sed -n 's/.*mCurrentFocus=.* //p' "$out/activity.txt" | head -n 1)"
crash_count="$(rg -ci 'FATAL EXCEPTION|Fatal signal|SIGSEGV|SIGABRT' "$out/logcat.txt" || true)"

graphics_pss="$(awk '/Graphics:/ {print $2; exit}' "$out/meminfo.txt" || true)"
native_pss="$(awk '/Native Heap:/ {print $3; exit}' "$out/meminfo.txt" || true)"
total_pss="$(awk '/TOTAL PSS:/ {print $3; exit}' "$out/meminfo.txt" || true)"

cat > "$out/summary.json" <<JSON
{
  "serial": "${serial}",
  "package": "${package}",
  "versionName": "${version_name}",
  "versionCode": "${version_code}",
  "foreground": "${foreground}",
  "crashSignals": ${crash_count:-0},
  "memoryKb": {
    "graphics": "${graphics_pss:-unknown}",
    "nativeHeap": "${native_pss:-unknown}",
    "totalPss": "${total_pss:-unknown}"
  },
  "artifacts": ["getprop.txt", "activity.txt", "meminfo.txt", "gfxinfo.txt", "package.txt", "logcat.txt"]
}
JSON

cat "$out/summary.json"
echo "诊断文件：$out"
