#!/bin/sh
# shell/luci-apps.sh 的解析规则测试(用桩索引, 不联网)
# 用法: sh shell/tests/luci-apps-test.sh
# 退出码 0 = 全部通过; 1 = 有失败
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
LUCI_APPS="$REPO_ROOT/shell/luci-apps.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ✅ $1"; }
bad() { fail=$((fail + 1)); echo "  ❌ $1"; }

# 桩索引: 覆盖 i18n 优先 / mod 回退 / 只有 app / 完整包名 四种情况
cat > "$TMP/index.json" <<'EOF'
{
  "version": 2,
  "architecture": "x86_64",
  "packages": {
    "luci": "26.298.29275~c84adb9",
    "luci-app-ddns-go": "26.298.29275~c84adb9",
    "luci-app-firewall": "26.298.29275~c84adb9",
    "luci-app-nolang": "26.298.29275~c84adb9",
    "luci-app-wol": "26.298.29275~c84adb9",
    "luci-mod-status": "26.298.29275~c84adb9",
    "luci-mod-extra": "26.298.29275~c84adb9",
    "luci-i18n-ddns-go-zh-cn": "26.298.29275~c84adb9",
    "luci-i18n-firewall-zh-cn": "26.298.29275~c84adb9",
    "luci-i18n-wol-zh-cn": "26.298.29275~c84adb9",
    "luci-i18n-status-zh-cn": "26.298.29275~c84adb9"
  }
}
EOF
export LUCI_APPS_INDEX="$TMP/index.json"
export LUCI_APPS_CACHE="$TMP/cache"

# 1. 有 zh-cn 翻译 -> 用 i18n 包
out=$(sh "$LUCI_APPS" 25.12.2 ddns-go 2>&1)
if [ $? -eq 0 ] && [ "$out" = "luci-i18n-ddns-go-zh-cn " ]; then
  ok "有中文翻译时解析为 luci-i18n-<名>-zh-cn"
else
  bad "i18n 解析不对: $out"
fi

# 2. 只有 app 没有翻译 -> 用 luci-app-*
out=$(sh "$LUCI_APPS" 25.12.2 nolang 2>&1)
if [ $? -eq 0 ] && [ "$out" = "luci-app-nolang " ]; then
  ok "无中文翻译时解析为 luci-app-<名>"
else
  bad "app 解析不对: $out"
fi

# 3. mod 型应用: 有 zh-cn 的优先用 i18n 包
out=$(sh "$LUCI_APPS" 25.12.2 status 2>&1)
if [ $? -eq 0 ] && [ "$out" = "luci-i18n-status-zh-cn " ]; then
  ok "mod 型应用有翻译时同样优先用 i18n 包"
else
  bad "mod 型 i18n 解析不对: $out"
fi

# 3b. mod 型应用且没有翻译 -> 回退到 luci-mod-*
out=$(sh "$LUCI_APPS" 25.12.2 extra 2>&1)
if [ $? -eq 0 ] && [ "$out" = "luci-mod-extra " ]; then
  ok "mod 型应用无翻译时回退到 luci-mod-<名>"
else
  bad "mod 回退不对: $out"
fi

# 4. 以 luci- 开头 -> 按完整包名直接查
out=$(sh "$LUCI_APPS" 25.12.2 luci-app-firewall 2>&1)
if [ $? -eq 0 ] && [ "$out" = "luci-app-firewall " ]; then
  ok "完整包名直接查命中"
else
  bad "完整包名解析不对: $out"
fi

# 5. 完整包名不存在 -> 失败
out=$(sh "$LUCI_APPS" 25.12.2 luci-app-nope 2>&1)
if [ $? -ne 0 ] && printf '%s' "$out" | grep -q "没有这个包"; then
  ok "不存在的完整包名被拒"
else
  bad "不存在的完整包名未被拒: $out"
fi

# 6. 不存在的应用 -> 失败并列出候选
out=$(sh "$LUCI_APPS" 25.12.2 not-exist 2>&1)
if [ $? -ne 0 ] && printf '%s' "$out" | grep -q "没有这个 LuCI 应用" \
   && printf '%s' "$out" | grep -q "ddns-go"; then
  ok "不存在的应用被拒并列出该版本候选"
else
  bad "未知应用未被正确拒绝: $out"
fi

# 7. 通配 * -> 该版本全部 app(有 zh 的取 zh, 没有的取 app)
out=$(sh "$LUCI_APPS" 25.12.2 '*' 2>&1)
if [ $? -eq 0 ] && printf '%s' "$out" | grep -q "luci-i18n-ddns-go-zh-cn" \
   && printf '%s' "$out" | grep -q "luci-app-nolang" \
   && printf '%s' "$out" | grep -q "luci-i18n-wol-zh-cn" ; then
  ok "通配展开为该版本全部应用(有翻译取翻译, 无翻译取 app)"
else
  bad "通配展开不对: $out"
fi

# 8. 多个应用 -> 去重后输出
out=$(sh "$LUCI_APPS" 25.12.2 ddns-go ddns-go wol 2>&1)
if [ $? -eq 0 ] && [ "$out" = "luci-i18n-ddns-go-zh-cn luci-i18n-wol-zh-cn " ]; then
  ok "多应用去重输出"
else
  bad "多应用输出不对: $out"
fi

# 9. 非法版本号被拒
out=$(sh "$LUCI_APPS" 25.12 ddns-go 2>&1)
if [ $? -ne 0 ] && printf '%s' "$out" | grep -q "版本号格式非法"; then
  ok "非法版本号被拒"
else
  bad "版本号格式未校验: $out"
fi

# 10. 非法应用名被拒
out=$(sh "$LUCI_APPS" 25.12.2 "ddns go; rm -rf /" 2>&1)
if [ $? -ne 0 ] && printf '%s' "$out" | grep -q "应用名非法"; then
  ok "含 shell 元字符的应用名被拒"
else
  bad "应用名字符集未校验: $out"
fi

echo
echo "luci-apps-test: 通过 $pass, 失败 $fail"
[ "$fail" -eq 0 ] || exit 1
