#!/bin/sh
# 固件首启脚本(99-custom.sh)与构建脚本(build.sh)的契约断言
#
# 用法: sh shell/tests/firmware-config-test.sh
# 退出码 0 = 全部通过; 1 = 有失败
#
# 这两个脚本是一份跨越"构建期 -> 固件内 -> 首启"的对端契约:
#   build.sh 写出 /etc/config/pppoe-settings, 99-custom.sh 读它并配 PPPoE。
# 契约任一侧改了而另一侧没跟上, 不会让构建失败, 只会在设备上静默失效
# (比如密码被 shell 展开、PPPoE 根本没配上)。
# 这里把这份契约、以及首启脚本里几处"错了不报错"的逻辑做成硬断言。
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
CUSTOM="$REPO_ROOT/files/etc/uci-defaults/99-custom.sh"
BUILD="$REPO_ROOT/x86-64/build.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/build-x86-64.yml"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ✅ $1"; }
bad() { fail=$((fail + 1)); echo "  ❌ $1"; }

[ -f "$CUSTOM" ] || { echo "❌ 找不到 $CUSTOM" >&2; exit 1; }
[ -f "$BUILD" ]   || { echo "❌ 找不到 $BUILD" >&2; exit 1; }
[ -f "$WORKFLOW" ] || { echo "❌ 找不到 $WORKFLOW" >&2; exit 1; }

# ---- 通用工具: 从文件里抽出 IP 校验正则, 供实际测试用 ----
# workflow 里用 bash 的 =~, 脚本里用 grep -E。两者都吃 ERE, 所以抽出
# 同一份正则后可以同时喂给两边验证行为一致。
# 锚定到 CUSTOM_IP 那一行 —— 文件里还有别的 grep -Eq(比如接口名匹配),
# 不加锚定会抓错行。
extract_ip_regex() {
  sed -n "s/.*CUSTOM_IP.*grep -Eq '\([^']*\)'.*/\1/p" "$1" | head -1
}

IP_RE=$(extract_ip_regex "$CUSTOM")

# ================================================================
# 1. PPPoE 凭据: 读取侧不能用 . (source)
# ================================================================
# 源码里必须没有 `. "$SETTINGS_FILE"` / `. /etc/config/pppoe-settings` 这类
# source 写法。source 会把文件内容当 shell 代码再解析一遍, 密码里的
# $ ' " ; 会被展开或当成命令 —— 密码被静默篡改, 甚至执行注入的命令。
if grep -qE '^\s*\.\s+"?\$SETTINGS_FILE' "$CUSTOM"; then
  bad "99-custom.sh 仍在用 . (source) 读凭据文件, 密码里的 shell 元字符会被篡改"
else
  ok "99-custom.sh 不用 source 读凭据文件"
fi

# 读取方式必须是 uci get
if grep -q 'uci .*get .*pppoe-settings' "$CUSTOM"; then
  ok "99-custom.sh 用 uci get 读取凭据"
else
  bad "99-custom.sh 没有用 uci get 读取凭据"
fi

# ================================================================
# 2. PPPoE 凭据: 写入侧必须是 UCI 格式, 且不能有裸 heredoc 插值
# ================================================================
# 写入侧若用 << EOF (未加引号) 直接插值, 值会被 shell 处理;
# 必须是 UCI 双引号格式, 由 uci 负责转义。
if grep -qE 'cat << *EOF' "$BUILD" && grep -q 'PPPOE_PASSWORD=\${PPPOE_PASSWORD}' "$BUILD"; then
  bad "build.sh 仍用裸 heredoc 插值写密码, 特殊字符会被 shell 处理"
else
  ok "build.sh 不用裸 heredoc 插值写密码"
fi

if grep -q "config settings 'pppoe'" "$BUILD"; then
  ok "build.sh 按 UCI 格式写凭据文件"
else
  bad "build.sh 没有按 UCI 格式写凭据文件"
fi

# 三个凭据字段都必须真的用 uci 的 option 写出(不能只有部分字段走 uci 格式)
for field in enabled account password; do
  if grep -qE "option $field \"" "$BUILD"; then
    ok "build.sh 用 uci option 写出 $field"
  else
    bad "build.sh 没有用 uci option 写出 $field"
  fi
done

# 双引号是必须的: UCI 单引号值内部无法表示单引号本身
# (uci 源码 file.c parse_single_quote 没有反斜杠转义分支)。
# 要逐个字段查 —— 只查"有没有双引号"会被"三个里有一个用了双引号"骗过。
for field in enabled account password; do
  if grep -qE "option $field \"" "$BUILD"; then
    ok "build.sh 的 $field 用双引号包裹"
  else
    bad "build.sh 的 $field 没有用双引号包裹(单引号无法表示含单引号的密码)"
  fi
done

# 反斜杠与双引号必须被转义, 否则密码里的这两个字符会破坏 uci 语法
# 直接检查 sed 表达式本身: 反斜杠 s/\\/\\\\/g 与 双引号 s/"/\\"/g
if grep -qF "s/\\\\/\\\\\\\\/g" "$BUILD"; then
  ok "build.sh 转义了反斜杠"
else
  bad "build.sh 没有转义反斜杠"
fi
if grep -qF 's/"/\\"/g' "$BUILD"; then
  ok "build.sh 转义了双引号"
else
  bad "build.sh 没有转义双引号"
fi

# 读写两侧的字段名必须一致(这是最容易悄悄对不上的地方)
for field in enabled account password; do
  if grep -q "option $field " "$BUILD" && grep -q "pppoe-settings.pppoe.$field" "$CUSTOM"; then
    ok "凭据字段名两侧一致: $field"
  else
    bad "凭据字段名两侧不一致: $field (build.sh 写 option $field, 99-custom.sh 读 pppoe-settings.pppoe.$field)"
  fi
done

# ================================================================
# 3. 凭据文件读完后必须删除
# ================================================================
if grep -q 'rm -f "\$SETTINGS_FILE"' "$CUSTOM"; then
  ok "读完后删除凭据文件"
else
  bad "读完后没有删除凭据文件"
fi

# ================================================================
# 4. 管理地址校验: 必须逐段限 0-255
# ================================================================
if [ -z "$IP_RE" ]; then
  bad "没能从 99-custom.sh 里抽出 IP 校验正则(格式可能变了)"
else
  ok "抽出了 IP 校验正则"
  # 合法地址必须通过
  for ip in 192.168.1.1 10.0.0.1 255.255.255.255 0.0.0.0 172.16.31.254; do
    if printf '%s' "$ip" | grep -Eq "$IP_RE"; then
      ok "合法地址被接受: $ip"
    else
      bad "合法地址被误拒: $ip"
    fi
  done
  # 越界/畸形必须被拒 —— 这正是老正则放过的
  for ip in 256.1.1.1 999.999.999.999 192.168.1.256 300.1.1.1 1.2.3 1.2.3.4.5 "" "192.168.1.1 "; do
    if printf '%s' "$ip" | grep -Eq "$IP_RE"; then
      bad "非法地址被误收: [$ip]"
    else
      ok "非法地址被拒绝: [$ip]"
    fi
  done
fi

# workflow 侧必须用同一份正则(两处必须同步, 否则 CI 放行但脚本仍会写坏值)
# workflow 里是 bash =~ 语法, 正则没有被引号包裹, 用 grep -o 按 "=~ ^...$" 截取。
# 只取第一处匹配 —— profile 那条校验的正则形态不同, 不会被误取。
WF_RE=$(grep -o '=~ \^.*\$' "$WORKFLOW" | head -1 | sed 's/^=~ //')
if [ -z "$WF_RE" ]; then
  bad "没能从 workflow 里抽出 IP 校验正则"
elif [ "$WF_RE" = "$IP_RE" ]; then
  ok "workflow 与 99-custom.sh 的 IP 正则一致"
else
  bad "workflow 与 99-custom.sh 的 IP 正则不一致, 两处必须同步"
fi

# ================================================================
# 5. 固件大小: 只支持单档
# ================================================================
# ImageBuilder 的产物文件名不含 rootfs 大小, 多档会写进同一路径互相覆盖,
# 最终只剩最后一档 —— 所以工作流不能提供多档入口。
if grep -q 'profile_array' "$WORKFLOW"; then
  bad "workflow 仍在按逗号分隔多档构建, 多档会互相覆盖只剩最后一档"
else
  ok "workflow 只构建单档固件"
fi
if grep -qE 'profile:.*(逗号|多个)' "$WORKFLOW"; then
  bad "workflow 的 profile 输入说明仍宣称支持多档"
else
  ok "workflow 的 profile 输入说明已与单档实现一致"
fi
# 单档也要校验是正整数, 否则 ROOTFS_PARTSIZE 会拿到无效值
if grep -qF '=~ ^[1-9][0-9]*$' "$WORKFLOW"; then
  ok "workflow 校验 profile 为正整数"
else
  bad "workflow 没有校验 profile 是正整数"
fi

# ================================================================
# 6. 首启脚本不该有"错了不报错"的结构
# ================================================================
# 裸 uci commit 会把其它 uci-defaults 脚本在同一批次留下的半成品改动一起写盘
if grep -qE '^\s*uci commit\s*$' "$CUSTOM"; then
  bad "99-custom.sh 仍有裸 uci commit, 会提交其它脚本的半成品改动"
else
  ok "99-custom.sh 没有裸 uci commit"
fi

# docker 防火墙段不应再用 cat >> 追加原文(绕过 uci 校验与规范化)
if grep -qE 'cat << *EOF *>>' "$CUSTOM"; then
  bad "99-custom.sh 仍用 cat >> 追加 uci 配置, 绕过了 uci 的校验"
else
  ok "99-custom.sh 不用 cat >> 追加 uci 配置"
fi

# docker zone 必须真的写进 uci
if grep -q 'uci set firewall.docker=zone' "$CUSTOM"; then
  ok "docker zone 用 uci 写入"
else
  bad "docker zone 没有用 uci 写入"
fi

# docker zone 必须声明子网, 否则容器流量不归属该 zone, 三条 forwarding 全部失效,
# 表现为容器无法联网。172.16.0.0/12 恰好覆盖 Docker 全部默认地址池
# (172.17~172.31), 是有意选的宽范围, 不是写错的孤链。
if grep -q "firewall.docker.subnet='172.16.0.0/12'" "$CUSTOM"; then
  ok "docker zone 声明了 172.16.0.0/12 子网"
else
  bad "docker zone 缺少子网声明, 容器流量将不匹配该 zone 而无法联网"
fi

# 三条 forwarding 都要有
if [ "$(grep -c 'uci add firewall forwarding' "$CUSTOM")" -eq 3 ]; then
  ok "三条 docker forwarding 都用 uci 添加"
else
  bad "docker forwarding 数量不对(应为 3 条 uci add)"
fi

# 首启脚本不该有硬编码的外部域名/IP 解析映射。
# 这类映射(如 time.android.com -> 某个 IP)是写死的外部依赖: 目标 IP 变了
# 就失效, 且固件带着别人的域名走。已从脚本移除, 这里加断言防它被加回来。
if grep -qE '(DOMAIN_NAME|DOMAIN_IP|uci add dhcp domain)' "$CUSTOM"; then
  bad "99-custom.sh 又有硬编码的域名/IP 解析映射, 属于不该存在的外部依赖"
else
  ok "99-custom.sh 无硬编码域名/IP 解析映射"
fi

# x86-64 仓库不该有板型硬编码特例(固件内无 board.json, 永不命中)
if grep -qE 'radxa,e20c|friendlyarm,nanopi-r5c' "$CUSTOM"; then
  bad "99-custom.sh 仍有 x86-64 用不上的板型硬编码特例"
else
  ok "99-custom.sh 无板型硬编码特例"
fi

# ================================================================
# 6b. 首启脚本的文件卫生与作用域
# ================================================================
# 日志不能写 /etc/config: 那里只应放 UCI 配置。混进 .txt 会让无参 uci show
# 解析整个目录时报 Parse error, 也容易被当成配置一起备份/恢复。
if grep -q 'LOGFILE="/etc/config/' "$CUSTOM"; then
  bad "99-custom.sh 又把日志写进 /etc/config 了, 会污染 UCI 配置目录"
else
  ok "99-custom.sh 不往 /etc/config 写日志"
fi

# 构建期塞进 /etc/config 的 custom_router_ip.txt 读完必须删掉
if grep -q 'rm -f "\$IP_VALUE_FILE"' "$CUSTOM"; then
  ok "custom_router_ip.txt 读完即删"
else
  bad "custom_router_ip.txt 用完不删, 会长期留在设备 /etc/config"
fi

# WAN 入站放行只能发生在单网口分支:
# 多网口设备用 LAN 静态地址访问, 把 WAN 开成 ACCEPT 只是白白扩大暴露面。
if awk '/count" -eq 1/{g=NR} /^[[:space:]]*open_wan_input[[:space:]]*$/{c=NR} END{exit !(g && c && c>g && c-g<=6)}' "$CUSTOM"; then
  ok "WAN 入站放行只出现在单网口分支"
else
  bad "WAN 入站放行没有限定在单网口分支(多网口也会把 WAN 开成 ACCEPT)"
fi

# zone 查找必须兼容具名段(config zone 'wan'), 不能只匹配 @zone[N] 形态
if grep -q 'find_wan_zone' "$CUSTOM" && ! grep -q 'wan_zone=$(uci show firewall' "$CUSTOM"; then
  ok "wan zone 查找兼容匿名段与具名段"
else
  bad "wan zone 查找仍只认匿名段(@zone[N]), 具名 zone 配置下会找不到"
fi

# 删 docker forwarding 必须按 section 标识, 不能按数组下标:
# 具名段(config forwarding 'xxx')取不到下标, 老写法会漏删。
if grep -q 'cut -d\[ -f2' "$CUSTOM"; then
  bad "docker forwarding 仍按数组下标删除, 具名 forwarding 段会漏删"
else
  ok "docker forwarding 按 section 标识删除(具名段不会漏删)"
fi

# ================================================================
# 7. 若环境里有 uci, 跑真实的凭据往返测试
# ================================================================
# CI 的 ubuntu runner 没有 uci, 这一段会自动跳过; 本机或 OpenWrt 环境下
# 可以真正验证"写入的密码读回来一模一样"。
if command -v uci >/dev/null 2>&1; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  mkdir -p "$TMP/etc/config"

  # 复现 build.sh 里的转义函数与写入格式。
  # 注意: 不能 source build.sh —— 它会真的去执行 make image。
  uci_escape_dq() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
  }

  for pw in 'pa$$word' "with'quote" 'with"dquote' 'with;semicolon' 'with\backslash' 'plain' 'sp ace'; do
    {
      printf "config settings 'pppoe'\n"
      printf '\toption enabled "%s"\n' "yes"
      printf '\toption account "%s"\n' "$(uci_escape_dq "acct$pw")"
      printf '\toption password "%s"\n' "$(uci_escape_dq "$pw")"
    } > "$TMP/etc/config/pppoe-settings"

    got=$(uci -c "$TMP/etc/config" -q get pppoe-settings.pppoe.password 2>/dev/null)
    if [ "$got" = "$pw" ]; then
      ok "凭据往返无损: [$pw]"
    else
      bad "凭据往返被破坏: 写入 [$pw] 读回 [$got]"
    fi
  done
else
  echo "  ⏭️  环境无 uci, 跳过真实凭据往返测试(CI runner 无 uci 属正常)"
fi

echo
echo "firmware-config-test: 通过 $pass, 失败 $fail"
[ "$fail" -eq 0 ] || exit 1
