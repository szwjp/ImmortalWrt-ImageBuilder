#!/bin/sh
# 按"本次构建版本"把 LuCI 应用名解析成该版本真实存在的包名
#
# 用法: sh shell/luci-apps.sh <version> <app1> [app2 ...]
#   version 形如 25.12.2
#
# 数据源: 官方源的索引 index.json (packages 字典: 包名 -> 版本)
#   https://downloads.immortalwrt.org/releases/<version>/packages/x86_64/luci/index.json
#   用索引而不是目录列表: 索引是权威的包名->版本映射, 一行一条, 解析无歧义,
#   也不受目录列表排版/分页影响。
#
# 解析规则(按序尝试):
#   1) luci-i18n-<名>-zh-cn 存在 -> 用它
#      (i18n 包本身依赖对应的 app 包, apk 解析依赖时会自动带上依赖闭包)
#   2) 否则 luci-app-<名> 存在   -> 用它(该版本没有中文翻译)
#   3) 否则 luci-mod-<名> 存在   -> 用它(该版本是 mod 型包, 如 status/overview)
#   4) 都没有                    -> 构建失败, 并列出该版本可用的应用名
#
# 特殊形式:
#   "*"      -> 该版本全部 luci-app-*(有 zh-cn 的取 zh-cn, 其余取 app)
#   "luci-*" -> 以 luci- 开头按完整包名直接查(存在即用)
#
# 环境变量:
#   LUCI_APPS_CACHE   索引缓存目录(默认 ${TMPDIR:-/tmp}/luci-index-<version>)
#   LUCI_APPS_INDEX   直接指定本地 index.json(测试用; 设了就不联网)
set -eu

if [ $# -lt 1 ]; then
  echo "用法: sh shell/luci-apps.sh <version> <app...>" >&2
  exit 1
fi

VERSION="$1"; shift

case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "❌ 版本号格式非法: '$VERSION' (应形如 25.12.2)" >&2; exit 1 ;;
esac

FEED_BASE="https://downloads.immortalwrt.org/releases/$VERSION/packages/x86_64/luci"
CACHE_DIR="${LUCI_APPS_CACHE:-${TMPDIR:-/tmp}/luci-index-$VERSION}"
INDEX="$CACHE_DIR/index.json"

if [ -n "${LUCI_APPS_INDEX:-}" ]; then
  INDEX="$LUCI_APPS_INDEX"
  [ -f "$INDEX" ] || { echo "❌ 指定的索引不存在: $INDEX" >&2; exit 1; }
else
  mkdir -p "$CACHE_DIR"
  if [ ! -s "$INDEX" ]; then
    echo "🔄 抓取 $VERSION 的 luci 源索引..."
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL --retry 3 --retry-delay 2 "$FEED_BASE/index.json" -o "$INDEX.tmp" \
        || { echo "❌ 拉取 luci 源索引失败: $FEED_BASE/index.json" >&2; exit 1; }
    else
      wget -q -O "$INDEX.tmp" "$FEED_BASE/index.json" \
        || { echo "❌ 拉取 luci 源索引失败: $FEED_BASE/index.json" >&2; exit 1; }
    fi
    mv -f "$INDEX.tmp" "$INDEX"
  fi
fi

# 从索引里取出全部包名 (index.json 一行一条 "包名": "版本")
mkdir -p "$CACHE_DIR"
PKG_LIST="$CACHE_DIR/pkg-names.txt"
if [ ! -s "$PKG_LIST" ] || [ "$INDEX" -nt "$PKG_LIST" ]; then
  grep -oE '"[^"]+":' "$INDEX" | sed 's/^"//; s/":$//' | LC_ALL=C sort -u > "$PKG_LIST"
fi
[ -s "$PKG_LIST" ] || { echo "❌ 索引里没解析出任何包名: $INDEX" >&2; exit 1; }

have() { grep -qxF "$1" "$PKG_LIST"; }

# 该版本可用的应用名(luci-app-* 去前缀), 报错时列给用户看
list_apps() {
  grep -E '^luci-app-' "$PKG_LIST" | sed 's/^luci-app-//' | LC_ALL=C sort -u
}

OUT=""
for app in "$@"; do
  if [ "$app" = "*" ]; then
    for p in $(grep -E '^luci-app-' "$PKG_LIST" | LC_ALL=C sort -u); do
      zh="luci-i18n-${p#luci-app-}-zh-cn"
      if have "$zh"; then OUT="$OUT $zh"; else OUT="$OUT $p"; fi
    done
    continue
  fi
  case "$app" in
    "" | *[!a-zA-Z0-9._+-]*)
      echo "❌ 应用名非法: '$app'" >&2
      exit 1
      ;;
  esac
  # 以 luci- 开头: 按完整包名直接查
  case "$app" in
    luci-*)
      if have "$app"; then
        OUT="$OUT $app"
      else
        echo "❌ 该版本($VERSION)没有这个包: $app" >&2
        exit 1
      fi
      continue
      ;;
  esac
  if have "luci-i18n-$app-zh-cn"; then
    OUT="$OUT luci-i18n-$app-zh-cn"
  elif have "luci-app-$app"; then
    OUT="$OUT luci-app-$app"
  elif have "luci-mod-$app"; then
    OUT="$OUT luci-mod-$app"
  else
    echo "❌ 该版本($VERSION)没有这个 LuCI 应用: $app" >&2
    echo "   该版本可用的应用名(前 40 个):" >&2
    list_apps | head -40 | sed 's/^/   /' >&2
    exit 1
  fi
done

# 去重后输出
printf '%s\n' $OUT | awk 'NF && !seen[$0]++' | tr '\n' ' '
echo
