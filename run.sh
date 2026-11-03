#!/bin/bash
# 以"鼠标平移"模式启动 Astris：仅本次进程注入 dylib，不改动 Astris.app。
# 从 Dock / Finder 正常打开 Astris 即为原生状态。
#
# 用法：./run.sh [游戏文件 ...]   给了游戏文件会在启动后自动打开。
# 默认后台启动并脱离终端（关终端、Ctrl-C 都不影响游戏）。
# 需要前台看实时日志时：ASTRIS_MOUSE_FOREGROUND=1 ./run.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="${ASTRIS_APP:-/Applications/Astris.app}"
BIN="$APP/Contents/MacOS/Astris"
DYLIB="$DIR/build/libAstrisMouse.dylib"
LOG="$HOME/Library/Logs/AstrisMouse.log"

if [ ! -x "$BIN" ]; then
  echo "找不到 $BIN" >&2
  exit 1
fi

if [ ! -f "$DYLIB" ] || [ ! -x "$DIR/build/astris-launch" ]; then
  "$DIR/build.sh"
fi

if pgrep -xq Astris; then
  echo "Astris 已在运行。请先完全退出 Astris（⌘Q）再执行本脚本，避免开出第二个实例。" >&2
  exit 1
fi

if pgrep -xq MacRMB; then
  echo "提示：MacRMB 正在运行。两者可以共存，但不要同时开启两边的平移（MacRMB 是 ⌥⌘P，这里默认 ⌥⌘M）。" >&2
fi

if [ -f "$DIR/config.env" ]; then
  # shellcheck disable=SC1091
  source "$DIR/config.env"
fi

mkdir -p "$(dirname "$LOG")"
echo "日志：$LOG"
echo "切换平移：按 ${ASTRIS_MOUSE_TOGGLE:-cmd+alt+m}，或执行 notifyutil -p dev.astrismouse.toggle"
echo "调参：改 $DIR/config.env 保存即生效，不用重启（ASTRIS_MOUSE_TAKEOVER 除外）"

# DYLD_INSERT_LIBRARIES 只能出现在 Astris 自己的环境里：astris-launch 在 fork 之后才设置它，
# 不能 export，也不能经过 nohup/env/tee 等系统二进制（它们会尝试加载并失败）。
# -c 让 astris-launch 顺带监视 config.env，改动实时送进 Astris。
if [ "${ASTRIS_MOUSE_FOREGROUND:-0}" = "1" ]; then
  if [ $# -gt 0 ]; then
    (sleep 4 && open -a "$APP" "$@") &
  fi
  exec "$DIR/build/astris-launch" -f -c "$DIR/config.env" "$DYLIB" "$LOG" "$BIN" 2>&1 | tee -a "$LOG"
fi

PID="$("$DIR/build/astris-launch" -c "$DIR/config.env" "$DYLIB" "$LOG" "$BIN")"
sleep 1
if kill -0 "${PID}" 2>/dev/null; then
  echo "Astris 已在后台启动（pid ${PID}）。查看日志：tail -f \"${LOG}\""
else
  echo "启动失败，请查看日志：${LOG}" >&2
  exit 1
fi

if [ $# -gt 0 ]; then
  sleep 3
  open -a "$APP" "$@"
  echo "已请求打开：$*"
fi
