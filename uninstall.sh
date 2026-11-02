#!/bin/bash
# 回滚：删除编译产物与日志。Astris.app 本体从未被修改，无需任何恢复操作。
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

if pgrep -xq Astris; then
  echo "Astris 正在运行，请先退出再执行。" >&2
  exit 1
fi

rm -rf "$DIR/build"
rm -f "$HOME/Library/Logs/AstrisMouse.log"
echo "已删除 $DIR/build 与日志。"
echo "Astris.app 从未被改动；直接从 Dock / Finder 打开即为原生状态。"
echo "如需彻底移除，删除整个目录即可：rm -rf \"$DIR\""
