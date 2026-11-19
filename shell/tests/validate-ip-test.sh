#!/bin/sh
# 管理地址校验(shell/validate-ip.sh)的行为测试
#
# 用法: sh shell/tests/validate-ip-test.sh
# 退出码 0 = 全部通过; 1 = 有失败
#
# 这里测的是"能不能写进 network.lan.ipaddr 并绑得上", 不是"像不像 IP":
# 旧测试把 0.0.0.0、255.255.255.255 当成合法地址, 等于在保护错误行为。
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
VALIDATE="$REPO_ROOT/shell/validate-ip.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ✅ $1"; }
bad() { fail=$((fail + 1)); echo "  ❌ $1"; }

[ -f "$VALIDATE" ] || { echo "❌ 找不到 $VALIDATE" >&2; exit 1; }

# ---- 命令行接口 ----
for ip in 192.168.1.1 10.0.0.1 172.16.31.254 192.168.1.254 10.255.255.1 223.255.255.254; do
  if sh "$VALIDATE" "$ip" >/dev/null 2>&1; then
    ok "接受可用主机地址: $ip"
  else
    bad "误拒可用主机地址: $ip"
  fi
done

for ip in \
  0.0.0.0 255.255.255.255 \
  192.168.1.0 192.168.1.255 10.0.0.0 10.0.0.255 \
  127.0.0.1 127.1.2.3 \
  169.254.1.1 \
  224.0.0.1 239.255.255.254 240.0.0.1 \
  256.1.1.1 999.999.999.999 300.1.1.1 \
  1.2.3 1.2.3.4.5 192.168.01.1 \
  '192.168.1.1 ' ' 192.168.1.1' '192.168.1.1\t'; do
  if sh "$VALIDATE" "$ip" >/dev/null 2>&1; then
    bad "误收非法地址: [$ip]"
  else
    ok "拒绝非法地址: [$ip]"
  fi
done

if sh "$VALIDATE" '' >/dev/null 2>&1; then
  bad "空字符串被判为合法"
else
  ok "空字符串被拒绝"
fi

# ---- 函数接口(source 到首启脚本里的用法) ----
. "$VALIDATE"
if ip_is_usable 192.168.1.1; then
  ok "source 后函数可用: 192.168.1.1"
else
  bad "source 后函数误拒 192.168.1.1"
fi
for ip in 0.0.0.0 255.255.255.255 127.0.0.1 192.168.1.0 192.168.1.255; do
  if ip_is_usable "$ip"; then
    bad "source 后函数误收: $ip"
  else
    ok "source 后函数拒绝: $ip"
  fi
done

echo
echo "validate-ip-test: 通过 $pass, 失败 $fail"
[ "$fail" -eq 0 ] || exit 1
