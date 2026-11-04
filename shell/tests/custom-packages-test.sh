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

# ---- 从源文件里取出清单 ----
# 原始字符串(raw)与拆分后的词表(words)都要:
#   raw  用来校验"整体格式"(不能有多余空格/换行/非法字符),
#        否则 "ac me" 这种带空格的错误会在按空格拆分后变成两个合法单词而被漏掉
#   words 用来做逐项检查(重复、重名等)
# 只取未注释的赋值行; 注释掉的包不算启用
core_raw=$(grep -E '^[[:space:]]*CUSTOM_PACKAGES=' "$SRC" \
  | grep -v 'CUSTOM_PACKAGES=""' \
  | sed 's/.*CUSTOM_PACKAGES="\$CUSTOM_PACKAGES //; s/"$//' \
  | tr '\n' ' ' | sed 's/ *$//')

exclude_raw=$(grep -E '^[[:space:]]*EXCLUDE_PACKAGES=' "$SRC" \
  | sed 's/^[[:space:]]*EXCLUDE_PACKAGES="//; s/"$//')

core_pkgs=$(printf '%s\n' "$core_raw" | tr ' ' '\n' | grep -v '^$')
exclude_pkgs=$(printf '%s\n' "$exclude_raw" | tr ' ' '\n' | grep -v '^$')

core_count=$(printf '%s\n' "$core_pkgs" | grep -c .)

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

# 3. 静态表里的 LuCI 应用只能写 luci-i18n-* 形式
#    官方 LuCI 应用的包名直接写在 custom-packages.sh 里(不做按版本解析),
#    因此包名必须写对。写错的形式有两种典型:
#      - 写成 luci-app-<名> / luci-mod-<名>: 这是应用本体, 装了没有中文界面
#      - 写成 luci-i18n-<名>-zh-cn 但该应用其实没有中文翻译: 装不上, 构建失败
#    例外是"非 i18n 的 LuCI 变体包", 它们不是翻译包而是 Web 后端实现
#    (luci-nginx: nginx+uwsgi 形态), 必须显式列进白名单, 否则直接判不合规。
LUCI_VARIANT_ALLOW="luci-nginx"
non_i18n=$(printf '%s\n' "$core_pkgs" \
  | grep -E '^luci-' \
  | grep -vE "^luci$|^luci-i18n-[a-z0-9._-]+$|^(${LUCI_VARIANT_ALLOW})$" || true)
if [ -z "$non_i18n" ]; then
  ok "LuCI 包的写法合规(luci 本体 / luci-i18n-<名>-zh-cn / 白名单变体)"
else
  bad "LuCI 包写法不合规: $(echo "$non_i18n" | tr '\n' ' ')"
fi

# 4. 底线中文界面三件套必须在核心集里
#    这三个是底线界面(基础界面/防火墙/软件包页)的中文包, 少了任何一个,
#    首次开机的 WebUI 就不是中文。静态表里不要再重复写它们(会被第 2 条抓到)。
for p in luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn luci-i18n-package-manager-zh-cn; do
  if ! printf '%s\n' "$core_pkgs" | grep -qx -- "$p"; then
    bad "核心集缺底线包: $p"
  fi
done
if printf '%s\n' "$core_pkgs" \
  | grep -E '^luci-i18n-(base|firewall|package-manager)-zh-cn$' \
  | grep -c . | grep -qx 3; then
  ok "底线中文界面三件套齐全"
else
  bad "底线中文界面三件套不齐或重复"
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

# 10. 静态表里启用的 LuCI 应用, 包名形式必须正确
#     luci-i18n-<名>-zh-cn 是官方源里中文语言包的标准命名。
#     这里检查的是"写法", 不是"该版本有没有这个包"(后者是构建期 apk 报错的)。
#     另: 静态表里的包名如果拼错(如 luci-i18n-adblock-zhcn), 静态查不出来,
#     但 apk 在装包时会直接失败 —— 构建不会静默出错, 这点是安全的。
luci_pkgs=$(printf '%s
' "$core_pkgs" | grep -E '^luci-i18n-' || true)
luci_count=$(printf '%s\n' "$luci_pkgs" | grep -c .)
if [ "$luci_count" -gt 0 ]; then
  ok "静态表里启用了 $luci_count 个 LuCI 中文包"
else
  bad "静态表里一个 LuCI 中文包都没启用"
fi

# 11. 静态表里启用的包无重复
#     (第 2 条已在整体核心集上查过重复, 这里对 LuCI 子集再查一次,
#      便于报错时直接指向是哪几个包重了)
dup_luci=$(printf '%s\n' "$luci_pkgs" | sort | uniq -d)
if [ -z "$dup_luci" ]; then
  ok "静态表里的 LuCI 包无重复"
else
  bad "静态表里的 LuCI 包有重复: $(echo "$dup_luci" | tr '\n' ' ')"
fi

# 12. 静态表里的包名必须符合官方命名规范
#     luci-i18n-<名>-zh-cn: <名> 部分只允许小写字母/数字/./_/-
bad_name=$(printf '%s\n' "$luci_pkgs" | grep -vE '^luci-i18n-[a-z0-9._-]+-zh-cn$' || true)
if [ -z "$bad_name" ]; then
  ok "静态表里的包名符合 luci-i18n-<名>-zh-cn 规范"
else
  bad "静态表里包名不合规范: $(echo "$bad_name" | tr '\n' ' ')"
fi

# 13. 静态表里不能有 luci-i18n-<名>-zh-cn 与 luci-i18n-<名>-zh-cn 以外的大小写混写
#     ( apk 包名区分大小写, 写成 LuCI-I18N-... 之类的会装不上)
mixed_case=$(printf '%s\n' "$luci_pkgs" | grep -E '[A-Z]' || true)
if [ -z "$mixed_case" ]; then
  ok "静态表里的包名无大写字母"
else
  bad "静态表里包名含大写字母: $(echo "$mixed_case" | tr '\n' ' ')"
fi

# 14. docker 插件的包不能在静态表里启用
#     它由 workflow 的 include_docker 输入决定, 由 build.sh 按需追加。
#     若静态表里也启用, 就变成了"无论 include_docker 选什么都装",
#     输入项失效(用户选 no 也还是会装上)。
if printf '%s\n' "$core_pkgs" | grep -qx -- 'luci-i18n-dockerman-zh-cn'; then
  bad "静态表里启用了 luci-i18n-dockerman-zh-cn, 会让 include_docker 输入项失效"
else
  ok "docker 插件不在静态表里(由 include_docker 输入项控制)"
fi


# 15. build.sh 必须真的用上 EXCLUDE_PACKAGES
#     这里是"配置写了但没接线"的断点: 排除项不并进 PACKAGES 就是空转。
BUILD_SH="$REPO_ROOT/x86-64/build.sh"
if [ ! -f "$BUILD_SH" ]; then
  bad "找不到 $BUILD_SH"
else
  if grep -q 'EXCLUDE_PACKAGES' "$BUILD_SH"; then
    ok "build.sh 用上了 EXCLUDE_PACKAGES"
  else
    bad "build.sh 没引用 EXCLUDE_PACKAGES, 排除项不会生效"
  fi
  # PACKAGES 必须把核心集和排除项都并进去
  if grep -qE 'PACKAGES="\$CUSTOM_PACKAGES .*\$EXCLUDE_PACKAGES"' "$BUILD_SH"; then
    ok "build.sh 的 PACKAGES 并入了核心集与排除项"
  else
    bad "build.sh 的 PACKAGES 拼装没有同时包含核心集与排除项, 请核对拼接"
  fi
  # 已删除按版本解析机制, build.sh 里不该再有残留引用
  if grep -q 'luci-apps\.sh' "$BUILD_SH"; then
    bad "build.sh 里还引用着已删除的 luci-apps.sh"
  else
    ok "build.sh 无已删除机制的残留引用"
  fi
  # include_docker 输入项必须仍然有效(按需追加 dockerman 包)。
  # 注意要匹配"真正在追加包名的那一行", 而不是文件里出现过这个词:
  # 注释里也写着 luci-i18n-dockerman-zh-cn, 只 grep 关键词会误判成已接线。
  if grep -qE '^\s*PACKAGES="\$PACKAGES .*luci-i18n-dockerman-zh-cn"' "$BUILD_SH" \
     && grep -q 'INCLUDE_DOCKER' "$BUILD_SH"; then
    ok "build.sh 按 include_docker 追加 docker 插件包"
  else
    bad "build.sh 没按 include_docker 追加 dockerman 包, 该输入项已失效"
  fi
fi

echo
echo "custom-packages-test: 通过 $pass, 失败 $fail"
[ "$fail" -eq 0 ] || exit 1
