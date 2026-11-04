#!/bin/sh
# shell/refresh-release-date.sh 的行为测试(桩 gh, 不联网)
# 用法: sh shell/tests/refresh-release-date-test.sh
# 退出码 0 = 全部通过; 1 = 有失败
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
REFRESH="$REPO_ROOT/shell/refresh-release-date.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ✅ $1"; }
bad() { fail=$((fail + 1)); echo "  ❌ $1"; }

# 桩 gh: 记录调用序列到 $GH_LOG, 按 $GH_MODE 决定行为。
# 桩按被调用的子命令分支, 而不是按调用次序, 这样才能分别模拟
# "按 tag 查不到" 与 "列表接口也失败" 这两条不同路径。
make_stub() {
  cat > "$TMP/gh" <<'EOF'
#!/bin/sh
echo "$*" >> "$GH_LOG"
args="$*"
case "$args" in
  *"/releases/tags/"*)
    # 按 tag 查 release
    case "$GH_MODE" in
      notfound|api_down)
        echo "gh: Not Found (HTTP 404)" >&2
        exit 1
        ;;
      *)
        echo "365373554"
        exit 0
        ;;
    esac
    ;;
  *"per_page=100"*)
    # 列全部 release
    case "$GH_MODE" in
      api_down)
        echo "gh: server error" >&2
        exit 1
        ;;
      notfound)
        # release 确实不存在: 列表里没有该 tag
        echo "SomeOtherTag"
        exit 0
        ;;
      *)
        echo "Autobuild-x86-64"
        exit 0
        ;;
    esac
    ;;
  *"PATCH"*)
    # PATCH release
    case "$GH_MODE" in
      publish_fail_once)
        n=$(grep -c -- "-F draft=false" "$GH_LOG" 2>/dev/null || echo 0)
        if [ "$n" -le 1 ]; then
          echo "gh: boom" >&2
          exit 1
        fi
        echo "2026-11-04T08:00:00Z"
        exit 0
        ;;
      always_fail)
        echo "gh: boom" >&2
        exit 1
        ;;
      *)
        echo "2026-11-04T08:00:00Z"
        exit 0
        ;;
    esac
    ;;
  *)
    echo "2026-11-04T08:00:00Z"
    exit 0
    ;;
esac
EOF
  chmod +x "$TMP/gh"
}

export PATH="$TMP:$PATH"
export GH_LOG="$TMP/calls.log"

# 1. 正常路径: 先查 id, 再 draft=true, 再 draft=false
make_stub
: > "$GH_LOG"
out=$(GH_MODE=ok GH_TOKEN=dummy GITHUB_REPOSITORY=owner/repo \
  sh "$REFRESH" Autobuild-x86-64 2>&1)
calls=$(cat "$GH_LOG")
if printf '%s' "$calls" | grep -q "repos/owner/repo/releases/tags/Autobuild-x86-64" \
   && printf '%s' "$calls" | grep -q "PATCH repos/owner/repo/releases/.* -F draft=true" \
   && printf '%s' "$calls" | grep -q "PATCH repos/owner/repo/releases/.* -F draft=false"; then
  ok "调用序列正确: 查 tag -> draft=true -> draft=false"
else
  bad "调用序列不对: [$calls]"
fi
if printf '%s' "$calls" | grep -q "draft=true" \
   && printf '%s' "$calls" | grep -q "draft=false"; then
  ok "确实做了 draft -> published 往返(刷新 published_at 的关键)"
else
  bad "缺少 draft 往返: [$calls]"
fi

# 2. release 不存在 -> 静默跳过, 退出码 0
make_stub
: > "$GH_LOG"
out=$(GH_MODE=notfound GH_TOKEN=dummy GITHUB_REPOSITORY=owner/repo \
  sh "$REFRESH" Autobuild-x86-64 2>&1)
rc=$?
calls=$(cat "$GH_LOG")
if [ "$rc" -eq 0 ] && ! printf '%s' "$calls" | grep -q "PATCH"; then
  ok "release 不存在时静默跳过(首次构建不失败)"
else
  bad "release 不存在时行为不对: rc=$rc calls=[$calls]"
fi

# 3. API 整体不可用 -> 必须报错退出, 不能当成"不存在"静默放过
#    (否则一次网络抖动就让刷新步骤白跑, 日期又停在旧值)
make_stub
: > "$GH_LOG"
out=$(GH_MODE=api_down GH_TOKEN=dummy GITHUB_REPOSITORY=owner/repo \
  sh "$REFRESH" Autobuild-x86-64 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "刷新中止"; then
  ok "API 故障时报错中止, 不误判成 release 不存在"
else
  bad "API 故障时未报错中止: rc=$rc out=$out"
fi

# 4. 第一次 publish 失败 -> 自动重试一次并成功
make_stub
: > "$GH_LOG"
out=$(GH_MODE=publish_fail_once GH_TOKEN=dummy GITHUB_REPOSITORY=owner/repo \
  sh "$REFRESH" Autobuild-x86-64 2>&1)
rc=$?
calls=$(cat "$GH_LOG")
n_false=$(printf '%s' "$calls" | grep -c -- "-F draft=false" || true)
if [ "$rc" -eq 0 ] && [ "$n_false" -eq 2 ]; then
  ok "publish 失败自动重试一次并最终成功"
else
  bad "重试逻辑不对: rc=$rc draft=false 次数=$n_false"
fi

# 5. 持续失败 -> 步骤失败(退出码非 0), 不能静默放过
make_stub
: > "$GH_LOG"
out=$(GH_MODE=always_fail GH_TOKEN=dummy GITHUB_REPOSITORY=owner/repo \
  sh "$REFRESH" Autobuild-x86-64 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  ok "持续失败时步骤失败(退出码非 0), 不静默放过"
else
  bad "持续失败时退出码应为非 0, 实际 $rc"
fi

# 6. 缺 GH_TOKEN -> 拒绝执行
make_stub
: > "$GH_LOG"
out=$(env -u GH_TOKEN GITHUB_REPOSITORY=owner/repo \
  sh "$REFRESH" Autobuild-x86-64 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "GH_TOKEN"; then
  ok "缺 GH_TOKEN 时拒绝执行"
else
  bad "缺 GH_TOKEN 未被拒: rc=$rc out=$out"
fi

# 7. 缺 tag 参数 -> 给出用法
make_stub
out=$(GH_TOKEN=dummy GITHUB_REPOSITORY=owner/repo sh "$REFRESH" 2>&1)
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "用法"; then
  ok "缺参数时给出用法"
else
  bad "缺参数未给用法: rc=$rc out=$out"
fi

echo
echo "refresh-release-date-test: 通过 $pass, 失败 $fail"
[ "$fail" -eq 0 ] || exit 1
