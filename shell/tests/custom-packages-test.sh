#!/bin/sh
# shell/custom-packages.sh 的静态断言测试(纯 shell, 不联网)
#
# 用法: sh shell/tests/custom-packages-test.sh
# 退出码 0 = 全部通过; 1 = 有失败
#
# 这个文件是"核心包集合 + 官方 LuCI 应用清单"的唯一事实源, 但它只是纯赋值,
# 写错一个包名/漏一个排除项不会让构建失败, 只会静默产出一份不对的固件。
# 这里把几条容易漂移、且漂移了不会自己报警的规则做成硬断言。
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
SRC="$REPO_ROOT/shell/custom-packages.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ✅ $1"; }
bad() { fail=$((fail + 1)); echo "  ❌ $1"; }

[ -f "$SRC" ] || { echo "❌ 找不到 $SRC" >&2; exit 1; }

# ---- 从源文件里取出三段清单 ----
# 原始字符串(raw)与拆分后的词表(words)都要:
#   raw  用来校验"整体格式"(不能有多余空格/换行/非法字符),
#        否则 "ac me" 这种带空格的错误会在按空格拆分后变成两个合法单词而被漏掉
#   words 用来做逐项检查(重复、重名等)
# 只取未注释的赋值行; 注释掉的包不算启用
core_raw=$(grep -E '^[[:space:]]*CUSTOM_PACKAGES=' "$SRC" \
  | grep -v 'CUSTOM_PACKAGES=""' \
  | sed 's/.*CUSTOM_PACKAGES="\$CUSTOM_PACKAGES //; s/"$//' \
  | tr '\n' ' ' | sed 's/ *$//')

luci_apps_raw=$(grep -E '^[[:space:]]*LUCI_APPS=' "$SRC" \
  | sed 's/^[[:space:]]*LUCI_APPS="//; s/"$//')

exclude_raw=$(grep -E '^[[:space:]]*EXCLUDE_PACKAGES=' "$SRC" \
  | sed 's/^[[:space:]]*EXCLUDE_PACKAGES="//; s/"$//')

core_pkgs=$(printf '%s\n' "$core_raw" | tr ' ' '\n' | grep -v '^$')
luci_apps=$(printf '%s\n' "$luci_apps_raw" | tr ' ' '\n' | grep -v '^$')
exclude_pkgs=$(printf '%s\n' "$exclude_raw" | tr ' ' '\n' | grep -v '^$')

core_count=$(printf '%s\n' "$core_pkgs" | grep -c .)
apps_count=$(printf '%s\n' "$luci_apps" | grep -c .)

# 1. 核心集非空
if [ "$core_count" -gt 0 ]; then
  ok "核心集非空($core_count 项)"
else
  bad "核心集为空"
fi

# 1b. 核心集原始字符串格式严格
#     核心集是逐行追加的, 每行一个包名; 拼起来必须是"单个空格分隔的合法包名",
#     不能有多余空格/换行(换行会破坏 make 的 PACKAGES 字符串)。
if printf '%s' "$core_raw" | grep -qE '  |^ | $'; then
  bad "核心集原始字符串有多余空格: [$core_raw]"
else
  ok "核心集无多余空格"
fi
if printf '%s' "$core_raw" | grep -qE "[^a-zA-Z0-9._+ -]"; then
  bad "核心集原始字符串含非法字符: [$core_raw]"
else
  ok "核心集原始字符串字符集合法"
fi

# 2. 核心集无重复
dup=$(printf '%s\n' "$core_pkgs" | sort | uniq -d)
if [ -z "$dup" ]; then
  ok "核心集无重复项"
else
  bad "核心集有重复: $(echo "$dup" | tr '\n' ' ')"
fi

# 3. 核心集里不能出现 luci-app-* / luci-mod-*
#    这两类是"某个 LuCI 应用本体", 属于 luci-apps.sh 按版本动态解析的职责。
#    核心集里写死它们, 就等于绕过了版本解析: 某个版本没有这个包时会构建失败,
#    或者静默装不上。核心集只允许 luci 本体和底线中文界面包。
stat_luci=$(printf '%s\n' "$core_pkgs" | grep -E '^luci-(app|mod)-' || true)
if [ -z "$stat_luci" ]; then
  ok "核心集无写死的 luci-app-*/luci-mod-* (交给 luci-apps.sh 按版本解析)"
else
  bad "核心集里写死了 luci-app-*/luci-mod-*: $(echo "$stat_luci" | tr '\n' ' ')"
fi

# 4. 核心集里不该有各应用的 luci-i18n-* 静态表
#    底线三个(base/firewall/package-manager)是例外: 它们属于底线中文界面, 明确保留。
i18n_static=$(printf '%s\n' "$core_pkgs" \
  | grep -E '^luci-i18n-' \
  | grep -vE '^luci-i18n-(base|firewall|package-manager)-zh-cn$' || true)
if [ -z "$i18n_static" ]; then
  ok "核心集无应用级 luci-i18n-* 静态表(仅保留 base/firewall/package-manager 底线包)"
else
  bad "核心集里写死了应用级 luci-i18n-*: $(echo "$i18n_static" | tr '\n' ' ')"
fi

# 5. 排除项格式: 必须是 "-包名"
#    ImageBuilder 的 PACKAGES 语义: "-pkgname" 表示从包里去掉该包
#    (Makefile:144 "-\"pkgname\" in the package list means remove \"pkgname\"")。
#    写成裸包名就变成"额外安装", 与意图相反; 写成 "-pkg name"(带空格)则会被
#    shell 拆成两个 token, 排除不掉任何东西。
bad_exclude=""
for e in $exclude_pkgs; do
  case "$e" in
    -) bad_exclude="$bad_exclude [$e:缺少包名]" ;;
    -*) ;;
    *) bad_exclude="$bad_exclude [$e:缺少前导减号]" ;;
  esac
done
if [ -z "$bad_exclude" ]; then
  ok "排除项格式正确($(printf '%s\n' "$exclude_pkgs" | grep -c .) 项, 均为 -包名)"
else
  bad "排除项格式不对:$bad_exclude"
fi

# 6. 排除项里不能有空格(会被 shell 拆成两个 token)
#    校验原始字符串而不是拆开的词表: "-autocore foo" 拆开后会变成两个都"合法"
#    的单词, 拆开看是发现不了的。
if printf '%s' "$exclude_raw" | grep -q ' '; then
  bad "排除项里有含空格的条目: [$exclude_raw]"
else
  ok "排除项无空格"
fi

# 6b. 排除项原始字符串只能由 "-包名" 组成, 整体格式严格
if printf '%s' "$exclude_raw" | grep -qE '^-[a-zA-Z0-9._+-]+( -[a-zA-Z0-9._+-]+)*$'; then
  ok "排除项原始字符串格式严格(-包名 空格分隔)"
else
  bad "排除项原始字符串格式不严格: [$exclude_raw]"
fi

# 7. 排除项无重复
dup_ex=$(printf '%s\n' "$exclude_pkgs" | sort | uniq -d)
if [ -z "$dup_ex" ]; then
  ok "排除项无重复"
else
  bad "排除项有重复: $(echo "$dup_ex" | tr '\n' ' ')"
fi

# 8. autocore 必须被排除
#    x86 的 ImageBuilder 默认会带上 autocore(自动调频), 与核心集口径不一致。
#    两条路径都要堵: .config 侧的 CONFIG_PACKAGE_autocore 和 ImageBuilder
#    target/linux/x86/Makefile 的 DEFAULT_PACKAGES。.config 侧由 imm.config
#    保证, 这里守 PACKAGES 侧。
if printf '%s\n' "$exclude_pkgs" | grep -qx -- '-autocore'; then
  ok "autocore 在排除列表里"
else
  bad "autocore 没被排除(固件会带上自动调频): 排除项=[$(echo "$exclude_pkgs" | tr '\n' ' ')]"
fi

# 9. 被排除的包不能同时出现在核心集里
#    否则"排除"被核心集的显式引入抵消, 排除就是空转
conflict=""
for e in $exclude_pkgs; do
  pkg=$(echo "$e" | sed 's/^-//')
  if printf '%s\n' "$core_pkgs" | grep -qx -- "$pkg"; then
    conflict="$conflict $pkg"
  fi
done
if [ -z "$conflict" ]; then
  ok "排除的包没有同时出现在核心集里(排除不是空转)"
else
  bad "被排除的包同时出现在核心集里:$conflict"
fi

# 10. LUCI_APPS 的每个条目都能被 luci-apps.sh 接受
#     这里不自己重新实现一遍"合法应用名"的判定, 而是直接调用 luci-apps.sh,
#     用它自己的校验规则说话(它的规则是: 非空 + 只含 [a-zA-Z0-9._+-])。
#     理由: 自己复制的规则迟早会和被测脚本不一致, 断言就成了空转。
#     做法: 按 LUCI_APPS 的条目造一个桩索引(每个条目都放进去), 让 luci-apps.sh
#     解析一遍。它若认为某个条目非法, 会报"应用名非法"并退出非 0。
#
#     注: LUCI_APPS 是空格分隔的清单, "ac me" 是两个条目(ac / me), 不是错误写法;
#     真正会失败的是"某个条目在索引里不存在", 那是构建期由 luci-apps.sh 报的,
#     不属于本测试的静态职责。
STUB_DIR=$(mktemp -d)
trap 'rm -rf "$STUB_DIR"' EXIT
stub_index="$STUB_DIR/index.json"
{
  echo '{'
  echo '  "packages": {'
  first=1
  for a in $luci_apps; do
    for cand in "luci-app-$a" "luci-i18n-$a-zh-cn"; do
      [ "$first" -eq 1 ] || echo ','
      first=0
      echo "    \"$cand\": \"1.0-r1\""
    done
    # 以 luci- 开头的条目走"完整包名直接查"路径, 桩里也要有它本身
    case "$a" in
      luci-*) [ "$first" -eq 1 ] || echo ','; first=0; echo "    \"$a\": \"1.0-r1\"" ;;
    esac
  done
  echo
  echo '  }'
  echo '}'
} > "$stub_index"

luci_out=$(LUCI_APPS_INDEX="$stub_index" LUCI_APPS_CACHE="$STUB_DIR/cache" \
  sh "$REPO_ROOT/shell/luci-apps.sh" 25.12.2 $luci_apps 2>"$STUB_DIR/err")
luci_rc=$?
if [ "$luci_rc" -eq 0 ]; then
  ok "LUCI_APPS 全部条目被 luci-apps.sh 接受($apps_count 个)"
else
  bad "luci-apps.sh 拒绝了某些 LUCI_APPS 条目: $(grep -v '^$' "$STUB_DIR/err" | head -3 | tr '\n' ' ')"
fi
if grep -q '应用名非法' "$STUB_DIR/err" 2>/dev/null; then
  bad "LUCI_APPS 含非法应用名: $(grep '应用名非法' "$STUB_DIR/err" | head -3 | tr '\n' ' ')"
else
  ok "LUCI_APPS 无非法应用名"
fi

# 11. LUCI_APPS 无重复
dup_app=$(printf '%s\n' "$luci_apps" | sort | uniq -d)
if [ -z "$dup_app" ]; then
  ok "LUCI_APPS 无重复应用"
else
  bad "LUCI_APPS 有重复应用: $(echo "$dup_app" | tr '\n' ' ')"
fi

# 12. LUCI_APPS 解析出来的包名与核心集无重名(不会重复装包)
#     用 luci-apps.sh 的真实解析结果来比对, 不自己枚举候选名:
#     解析规则以后若变了(新增候选形式), 这里自动跟着变。
resolved=$(printf '%s\n' "$luci_out" | tr ' ' '\n' | grep -v '^$' | LC_ALL=C sort -u)
overlap=""
for r in $resolved; do
  if printf '%s\n' "$core_pkgs" | grep -qx -- "$r"; then
    overlap="$overlap $r"
  fi
done
if [ -z "$overlap" ]; then
  ok "LUCI_APPS 解析结果与核心集无重名(不会重复装包)"
else
  bad "LUCI_APPS 解析结果与核心集重名:$overlap"
fi

# 13. 底线三件套必须在核心集里
#     这三个是底线中文界面, 不在 LUCI_APPS 里(见 custom-packages.sh 注释),
#     少了任何一个, 首次开机的 WebUI 就不是中文。
missing_base=""
for p in luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn luci-i18n-package-manager-zh-cn; do
  if ! printf '%s\n' "$core_pkgs" | grep -qx -- "$p"; then
    missing_base="$missing_base $p"
  fi
done
if [ -z "$missing_base" ]; then
  ok "底线中文界面三件套齐全"
else
  bad "核心集缺底线包:$missing_base"
fi

# 14. 底线三件套不能同时出现在 LUCI_APPS 里
#     它们已经是核心集的包, 再写进 LUCI_APPS 会解析出同一个包名(第 12 条会报),
#     这里单独点명, 便于定位到底是哪里写重了。
#     两条路径都查: 应用名"base", 以及直接写完整包名"luci-i18n-base-zh-cn"。
in_apps=""
for p in base firewall package-manager; do
  if printf '%s\n' "$luci_apps" | grep -qx -- "$p"; then
    in_apps="$in_apps $p"
  fi
  if printf '%s\n' "$luci_apps" | grep -qx -- "luci-i18n-$p-zh-cn"; then
    in_apps="$in_apps luci-i18n-$p-zh-cn"
  fi
done
if [ -z "$in_apps" ]; then
  ok "底线三件套未重复出现在 LUCI_APPS"
else
  bad "底线应用同时写进了 LUCI_APPS:$in_apps"
fi

# 14b. LUCI_APPS 里不该出现完整包名
#      这个清单的语义是"应用名"(见 custom-packages.sh 注释), 由 luci-apps.sh
#      按版本解析成真实包名。直接写完整包名虽然 luci-apps.sh 也支持(直接查),
#      但它绕过了版本解析: 该版本没有这个包时构建会失败, 或者装的是上个
#      版本才有的包。应用名才是这里该写的东西。
full_pkg=$(printf '%s\n' "$luci_apps" | grep -E '^luci-' || true)
if [ -z "$full_pkg" ]; then
  ok "LUCI_APPS 里写的都是应用名, 无完整包名"
else
  bad "LUCI_APPS 里写了完整包名(应写应用名): $(echo "$full_pkg" | tr '\n' ' ')"
fi

# 15. build.sh 必须真的用上 EXCLUDE_PACKAGES 与 luci-apps.sh
#     这两处是"配置写了但没接线"的断点: 排除项不并进 PACKAGES 就是空转,
#     LUCI_APPS 不经过解析就是一堆无效应用名。
BUILD_SH="$REPO_ROOT/x86-64/build.sh"
if [ ! -f "$BUILD_SH" ]; then
  bad "找不到 $BUILD_SH"
else
  if grep -q 'EXCLUDE_PACKAGES' "$BUILD_SH"; then
    ok "build.sh 用上了 EXCLUDE_PACKAGES"
  else
    bad "build.sh 没引用 EXCLUDE_PACKAGES, 排除项不会生效"
  fi
  if grep -q 'luci-apps\.sh' "$BUILD_SH"; then
    ok "build.sh 用上了 luci-apps.sh 做版本解析"
  else
    bad "build.sh 没调用 luci-apps.sh, LUCI_APPS 不会被解析成包名"
  fi
  # PACKAGES 必须把三段都并进去
  if grep -qE 'PACKAGES="\$CUSTOM_PACKAGES .*\$LUCI_PKGS .*\$EXCLUDE_PACKAGES"' "$BUILD_SH"; then
    ok "build.sh 的 PACKAGES 并入了核心集/解析结果/排除项三段"
  else
    bad "build.sh 的 PACKAGES 拼装没有同时包含三段, 请核对拼接顺序"
  fi
fi

echo
echo "custom-packages-test: 通过 $pass, 失败 $fail"
[ "$fail" -eq 0 ] || exit 1
