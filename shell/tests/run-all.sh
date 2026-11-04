#!/bin/sh
# 依次跑 shell/tests/ 下的全部测试
#
# 用法: sh shell/tests/run-all.sh
# 退出码 0 = 全部通过; 1 = 有失败
#
# CI 的 "Run shell tests" 步骤调用本脚本, 新增测试文件时只要放进
# shell/tests/ 就会被自动跑到, 不用改 workflow。
set -u

TESTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

failed=""
for t in "$TESTS_DIR"/*-test.sh; do
  [ -f "$t" ] || continue
  name=$(basename "$t")
  echo "=== $name ==="
  if sh "$t"; then
    :
  else
    failed="$failed $name"
  fi
  echo
done

if [ -n "$failed" ]; then
  echo "❌ 失败的测试:$failed"
  exit 1
fi

echo "✅ 全部测试通过"
