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

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)
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
# 4. 管理地址校验: 全项目只有一份实现(shell/validate-ip.sh)
# ================================================================
# 规则本身由 validate-ip-test.sh 做行为测试; 这里只断言"接线"对了:
# workflow、首启脚本、构建脚本都指向同一份文件, 没有任何一处再内联正则。
VALIDATE="$REPO_ROOT/shell/validate-ip.sh"
if [ -f "$VALIDATE" ]; then
  ok "存在唯一的校验实现 shell/validate-ip.sh"
else
  bad "缺少 shell/validate-ip.sh"
fi

if grep -qF '/usr/lib/imm/validate-ip.sh' "$CUSTOM" && grep -q 'ip_is_usable' "$CUSTOM"; then
  ok "99-custom.sh source 固件内的 validate-ip.sh 并调用 ip_is_usable"
else
  bad "99-custom.sh 没有 source /usr/lib/imm/validate-ip.sh 或没有调用 ip_is_usable"
fi

if grep -qE 'CUSTOM_IP.*grep -Eq|CUSTOM_IP.*=~' "$CUSTOM"; then
  bad "99-custom.sh 又内联了 IP 正则, 两份规则会漂移"
else
  ok "99-custom.sh 不再内联 IP 正则"
fi

if grep -qF 'sh shell/validate-ip.sh "$CUSTOM_ROUTER_IP"' "$WORKFLOW"; then
  ok "workflow 调用 shell/validate-ip.sh"
else
  bad "workflow 没有调用 shell/validate-ip.sh"
fi

if grep -qF 'shell/validate-ip.sh' "$BUILD" && grep -qF '/usr/lib/imm/validate-ip.sh' "$BUILD"; then
  ok "build.sh 把校验脚本拷进 /usr/lib/imm"
else
  bad "build.sh 没有把校验脚本拷进固件, 设备上会 source 不到"
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

# 首启脚本不该改 firewall 的 zone 入站策略。
# 单网口设备的唯一网口在默认配置里属于 lan zone(默认 input ACCEPT), 首访 WebUI
# 本来就能通; 给 wan zone 开 ACCEPT 既没用, 又会在以后有人加 wan 接口时白送放行。
if grep -qE 'open_wan_input|find_wan_zone|wan_zone' "$CUSTOM"; then
  bad "99-custom.sh 又出现 open_wan_input/find_wan_zone 之类的 WAN 放行逻辑"
elif awk '/count" -eq 1/{f=1} /count" -gt 1/{f=0} f && /firewall/' "$CUSTOM" | grep -q .; then
  bad "单网口分支又在改 firewall 配置"
else
  ok "单网口分支不修改 firewall zone 入站策略"
fi

# 删 docker forwarding 必须按 section 标识, 不能按数组下标:
# 具名段(config forwarding 'xxx')取不到下标, 老写法会漏删。
if grep -q 'cut -d\[ -f2' "$CUSTOM"; then
  bad "docker forwarding 仍按数组下标删除, 具名 forwarding 段会漏删"
else
  ok "docker forwarding 按 section 标识删除(具名段不会漏删)"
fi

# ================================================================
# 6c. 管理面默认收敛: SSH 只监听 lan, ttyd 默认关闭
# ================================================================
if grep -qF "dropbear.@dropbear[0].Interface='lan'" "$CUSTOM"; then
  ok "SSH 只监听 lan"
else
  bad "SSH 没有限制到 lan(默认会监听所有接口)"
fi
if grep -qF 'delete ttyd.@ttyd[0].interface' "$CUSTOM"; then
  bad "ttyd 仍被设置成监听所有接口"
else
  ok "ttyd 不再监听所有接口"
fi
if grep -qF '/etc/init.d/ttyd disable' "$CUSTOM"; then
  ok "ttyd 默认关闭"
else
  bad "ttyd 没有默认关闭(免密网页 shell 一直开着)"
fi
if grep -qF '/etc/banner' "$CUSTOM"; then
  ok "root 无密码时有登录 banner 提示"
else
  bad "root 无密码时没有提示"
fi

# ================================================================
# 6d. 单网口首启: 随机 root 密码
# ================================================================
# 单网口 DHCP 时设备就是上游局域网的一员, root 无密码等于管理权公开。
# 这里既断言「接上了」, 也断言实现本身没走样 —— 后者用行为测试: 把生成
# 函数按标记整段抽出来真跑, 而不是只 grep 源码字符串。
if grep -q '^# >>> first-boot-password' "$CUSTOM" && grep -q '^# <<< first-boot-password' "$CUSTOM"; then
  ok "随机密码函数有抽取标记(行为测试依赖它)"
else
  bad "随机密码函数的标记被删了, 行为测试会失效"
fi

if awk '/count" -eq 1/{f=1} /count" -gt 1/{f=0} f && /lockdown_single_nic_password/' "$CUSTOM" | grep -q .; then
  ok "单网口分支调用了随机密码设置"
else
  bad "单网口分支没有设置 root 密码, DHCP 接入上游网段就是空密码"
fi

# 已有密码必须跳过: 脚本可能被手动重跑, 不能每次都换掉用户的密码。
if grep -q 'root 已有密码' "$CUSTOM"; then
  ok "root 已有密码时跳过(重跑不改密码)"
else
  bad "缺少「已有密码就跳过」的判断, 重跑会把用户密码冲掉"
fi

# 密码是临时凭据, 绝不能进 /tmp/99-custom.log(会被回传给排查者)。
if grep 'LOGFILE' "$CUSTOM" | grep -q '\$pw'; then
  bad "随机密码被写进了日志"
else
  ok "随机密码不进日志"
fi

# 取密码的通道: 控制台(主) + /dev/tty1(兜底); 副本必须 600。
if grep -q '>/dev/console' "$CUSTOM" && grep -q '>/dev/tty1' "$CUSTOM"; then
  ok "密码输出到本机控制台(带 tty1 兜底)"
else
  bad "密码没有输出到控制台, 单网口机器将无法登录"
fi
if grep -q 'chmod 600 /root/.first-boot-password' "$CUSTOM"; then
  ok "密码副本权限 600"
else
  bad "密码副本没有收紧权限"
fi

# banner 在 SSH 登录前就会显示, 只能指向密码位置, 不能放密码本身。
if awk '/单网口首次启动已生成随机 root 密码/{f=1} f && /\$pw/{print; exit}' "$CUSTOM" | grep -q .; then
  bad "banner 段里出现了密码变量本身, 未认证的人就能看到密码"
else
  ok "banner 不含密码本身"
fi

if grep -q '/root/.first-boot-password' "$REPO_ROOT/README.md" 2>/dev/null; then
  ok "README 说明了密码副本位置"
else
  bad "README 没写密码从哪里取, 用户会卡在登录页"
fi

# --- 行为测试: 真跑生成函数 ---
gen_src=$(sed -n '/^# >>> first-boot-password/,/^# <<< first-boot-password/p' "$CUSTOM")
if [ -n "$gen_src" ]; then
  eval "$gen_src"
  bad_fmt=""
  ambiguous=""
  tmp_pw=$(mktemp)
  i=0
  while [ "$i" -lt 20 ]; do
    p=$(gen_first_boot_password)
    printf '%s\n' "$p" >>"$tmp_pw"
    if [ -z "$p" ]; then bad_fmt="空密码"; break; fi
    if [ "${#p}" -ne 16 ]; then bad_fmt="长度 ${#p}"; fi
    printf '%s' "$p" | grep -Eq '^[A-HJ-NP-Za-km-np-z2-9]{16}$' || bad_fmt="字符集越界: $p"
    printf '%s' "$p" | grep -q '[0O1lIo]' && ambiguous="$p"
    i=$((i + 1))
  done
  uniq_n=$(sort -u "$tmp_pw" | grep -c .)
  rm -f "$tmp_pw"
  if [ -z "$bad_fmt" ]; then
    ok "生成函数产出 16 位、字符集内、无易混字符的密码"
  else
    bad "生成函数产出异常($bad_fmt)"
  fi
  if [ -z "$ambiguous" ]; then
    ok "生成的密码不含 0/O/1/l/I/o"
  else
    bad "生成的密码含易混字符: $ambiguous"
  fi
  if [ "$uniq_n" -ge 19 ]; then
    ok "20 次生成几乎不重复(唯一 $uniq_n 个)"
  else
    bad "随机性不足: 20 次只有 $uniq_n 个不同值"
  fi
else
  bad "抽不到生成函数, 无法做行为测试"
fi

# ================================================================
# 6e. 网口枚举: 只认物理口, 且自动映射上限 9 个
# ================================================================
# /sys/class/net/* 的 glob 是字典序: 名字里出现两位数(eth10)后, eth10 会排在
# eth2 前面, 「最后一个口当 WAN」就静默配错。实测 10 口(eth0..eth9)仍正确,
# 错位从第 11 口开始; 脚本仍把上限取 9, 多留一档余量。
if grep -q '^MAX_PORTS=9$' "$CUSTOM"; then
  ok "端口数上限是 9(比实际错位点 11 留一档余量)"
else
  bad "没有把端口数上限定为 9, 11 口机的 WAN 会静默配错"
fi

if grep -q 'count" -gt "\$MAX_PORTS"' "$CUSTOM"; then
  ok "超过上限时跳过多网口自动映射"
else
  bad "缺少超限判断, 11 口机会按字典序最后一个口当 WAN"
fi

# 每个口的 MAC/驱动/PCI 必须进日志, 否则顺序错了没法排查。
if grep -q 'port \$port: mac=\$mac driver=\$driver pci=\$pci' "$CUSTOM"; then
  ok "首启日志记录每个口的 MAC/驱动/PCI"
else
  bad "日志没有记录网口细节, 顺序错配时无从排查"
fi

gen_ports_src=$(sed -n '/^# >>> list-physical-ports/,/^# <<< list-physical-ports/p' "$CUSTOM")
if [ -n "$gen_ports_src" ]; then
  eval "$gen_ports_src"
  fake_net=$(mktemp -d)

  # 9 口: 字典序 == 数字序, 最后一个必须是 eth8
  i=0
  while [ "$i" -le 8 ]; do mkdir -p "$fake_net/nine/eth$i/device"; i=$((i + 1)); done
  nine=$(list_physical_ports "$fake_net/nine")
  nine_n=$(echo "$nine" | wc -w)
  nine_last=$(echo "$nine" | awk '{print $NF}')
  if [ "$nine_n" -eq 9 ] && [ "$nine_last" = "eth8" ]; then
    ok "9 口按名字排序, 最后一个是 eth8"
  else
    bad "9 口排序异常: count=$nine_n last=$nine_last"
  fi

  # 10 口(eth0..eth9): 仍然正确 —— 这就是「上限 9 是保守值」的依据
  i=0
  while [ "$i" -le 9 ]; do mkdir -p "$fake_net/ten/eth$i/device"; i=$((i + 1)); done
  ten=$(list_physical_ports "$fake_net/ten")
  ten_n=$(echo "$ten" | wc -w)
  ten_last=$(echo "$ten" | awk '{print $NF}')
  if [ "$ten_n" -eq 10 ] && [ "$ten_last" = "eth9" ]; then
    ok "10 口(eth0..eth9)排序仍正确, 最后一个是 eth9"
  else
    bad "10 口排序异常: count=$ten_n last=$ten_last"
  fi

  # 11 口: 出现两位数名字, 字典序把 eth10 排到前面, 最后一个变成 eth9
  i=0
  while [ "$i" -le 10 ]; do mkdir -p "$fake_net/eleven/eth$i/device"; i=$((i + 1)); done
  eleven=$(list_physical_ports "$fake_net/eleven")
  eleven_last=$(echo "$eleven" | awk '{print $NF}')
  if [ "$eleven_last" = "eth9" ] && echo "$eleven" | grep -q 'eth10 eth2'; then
    ok "11 口复现字典序错位(eth10 排在 eth2 前, 最后一个是 $eleven_last)"
  else
    bad "11 口没有复现字典序错位: last=$eleven_last list=$eleven"
  fi

  # 虚拟口必须排除: gen 目录里只给 eth0/enp3s0 建 device 节点
  mkdir -p "$fake_net/mix/eth0/device" "$fake_net/mix/enp3s0/device"
  # lan*/wan* 是部分固件改过的物理口命名, 也要收; 但它们同样得有 device 节点
  mkdir -p "$fake_net/mix/lan1/device" "$fake_net/mix/wan0/device"
  mkdir -p "$fake_net/mix/lo" "$fake_net/mix/docker0" "$fake_net/mix/br-lan" "$fake_net/mix/veth0"
  mix=$(list_physical_ports "$fake_net/mix")
  # 顺序就是 glob 的字典序(enp3s0 在 eth0 前), 这里只比集合
  mix_sorted=$(printf "%s\n" $mix | sort | tr "\n" " ")
  if [ "$mix_sorted" = "enp3s0 eth0 lan1 wan0 " ]; then
    ok "虚拟口(lo/docker0/br-lan/veth)被排除"
  else
    bad "虚拟口混进了物理口列表: [$mix]"
  fi

  # 空目录不该崩, 也不该凭空造出口
  mkdir -p "$fake_net/empty"
  empty=$(list_physical_ports "$fake_net/empty")
  empty_n=$(echo "$empty" | wc -w)
  if [ "$empty_n" -eq 0 ]; then
    ok "无物理口时枚举返回空(不崩)"
  else
    bad "空目录枚举出 $empty_n 个口"
  fi

  rm -rf "$fake_net"
else
  bad "抽不到 list_physical_ports, 无法做枚举行为测试"
fi

# ================================================================
# 6f. br-lan 段解析 + 打包者后缀幂等
# ================================================================
# 老写法只认匿名段 @device[N], 具名段(config device 'brlan')找不到, 于是
# 端口不重排、LAN 不设地址, 脚本还照常 exit 0。这里用真实 uci show 的
# 输出格式做行为测试; 后缀那段则验证「重跑不叠加」。
if grep -q 'uci show network | find_brlan_section' "$CUSTOM"; then
  ok "br-lan 段通过 find_brlan_section 解析"
else
  bad "没有走 find_brlan_section, 具名段仍会漏"
fi

if grep -q '@?device\[' "$CUSTOM"; then
  bad "仍在用只认 @device[N] 的正则"
else
  ok "不再依赖匿名段命名"
fi

brlan_src=$(sed -n '/^# >>> brlan-section/,/^# <<< brlan-section/p' "$CUSTOM")
if [ -n "$brlan_src" ]; then
  eval "$brlan_src"
  got=$(printf "%s\n" "network.@device[0]=device" "network.@device[0].name='br-lan'" | find_brlan_section)
  if [ "$got" = "@device[0]" ]; then
    ok "匿名段 @device[0] 能识别"
  else
    bad "匿名段识别失败: [$got]"
  fi
  got=$(printf "%s\n" "network.brlan=device" "network.brlan.name='br-lan'" | find_brlan_section)
  if [ "$got" = "brlan" ]; then
    ok "具名段 brlan 也能识别"
  else
    bad "具名段识别失败: [$got]"
  fi
  got=$(printf "%s\n" "network.lan=interface" "network.lan.device='br-lan'" | find_brlan_section)
  if [ -z "$got" ]; then
    ok "只认 device 段的 .name, 不会被 lan.device 误导"
  else
    bad "误把 lan.device 当成 device 段: [$got]"
  fi
  got=$(printf "%s\n" "network.x=device" "network.x.name='br-lan2'" | find_brlan_section)
  if [ -z "$got" ]; then
    ok "br-lan2 之类近似名不会被误判"
  else
    bad "近似名被误判成 br-lan: [$got]"
  fi
else
  bad "抽不到 find_brlan_section, 无法做段解析行为测试"
fi

if grep -q 'add_packager_suffix /etc/openwrt_release' "$CUSTOM"; then
  ok "打包者后缀走 add_packager_suffix"
else
  bad "没有调用 add_packager_suffix, 重跑会叠加后缀"
fi

suffix_src=$(sed -n '/^# >>> packager-suffix/,/^# <<< packager-suffix/p' "$CUSTOM")
if [ -n "$suffix_src" ]; then
  eval "$suffix_src"
  rel_tmp=$(mktemp)
  printf "DISTRIB_DESCRIPTION='ImmortalWrt 25.12.2 r1'\n" > "$rel_tmp"
  add_packager_suffix "$rel_tmp"
  add_packager_suffix "$rel_tmp"
  add_packager_suffix "$rel_tmp"
  suffix_n=$(grep -o 'Packaged by szwjp' "$rel_tmp" | wc -l | tr -d ' ')
  if [ "$suffix_n" -eq 1 ]; then
    ok "重跑三次只追加一次后缀"
  else
    bad "后缀被叠加了 $suffix_n 次"
  fi
  if grep -q "DISTRIB_DESCRIPTION='ImmortalWrt 25.12.2 r1 (Packaged by szwjp)'" "$rel_tmp"; then
    ok "版本号原样保留, 只在末尾追加"
  else
    bad "版本行被改写坏了: $(cat "$rel_tmp")"
  fi
  if ( unset rel_tmp_ok; add_packager_suffix /nonexistent/openwrt_release ); then
    ok "文件不存在时安全返回(不报错)"
  else
    bad "文件不存在时返回了非 0"
  fi
  printf "DISTRIB_ID='ImmortalWrt'\n" > "$rel_tmp"
  add_packager_suffix "$rel_tmp"
  if grep -q 'Packaged by szwjp' "$rel_tmp"; then
    bad "没有 DISTRIB_DESCRIPTION 时也改了文件"
  else
    ok "没有 DISTRIB_DESCRIPTION 时保持原样"
  fi
  rm -f "$rel_tmp"
else
  bad "抽不到 add_packager_suffix, 无法做幂等测试"
fi

# ================================================================
# 6g. 结构性失败传播 / 幂等护栏 / 日志阶段 / 变量卫生
# ================================================================
# 结构性失败(br-lan 找不到、network 写盘失败)必须返回非 0, 让 uci-defaults
# 保留脚本下次重试; 环境差异类(没装 nginx/ttyd)保持 0, 否则重试会冲掉用户改动。
if grep -q '^STRUCT_FAIL=0$' "$CUSTOM" && grep -q 'exit "\$STRUCT_FAIL"' "$CUSTOM"; then
  ok "结构性失败用 STRUCT_FAIL 汇总并作为退出码"
else
  bad "没有 STRUCT_FAIL 汇总/退出, 失败会被 exit 0 吞掉"
fi

if awk '/cannot find device .br-lan/{found=1} found && /STRUCT_FAIL=1/{ok=1} END{exit !ok}' "$CUSTOM"; then
  ok "找不到 br-lan 会置结构性失败"
else
  bad "找不到 br-lan 时没有置位, LAN 半配置会被静默吞掉"
fi

# 三个分支原来只覆盖 >MAX_PORTS / ==1 / >1, 枚举到 0 个口时全部落空,
# 不配网络也不置位, exit 0 后脚本被删除 —— 静默半配置。
if grep -q 'elif \[ "\$count" -eq 0 \]; then' "$CUSTOM"; then
  ok "count=0 有独立分支(不再静默落空)"
else
  bad "count=0 时没有分支, 网络与密码保护都会被跳过且脚本仍被删除"
fi
if awk '/count" -eq 0/{f=1} /count" -eq 1/{f=0} f && /STRUCT_FAIL=1/{ok=1} END{exit !ok}' "$CUSTOM"; then
  ok "count=0 置结构性失败(问题每次启动可见)"
else
  bad "count=0 分支没有置位"
fi

net_commit_guard=$(grep -A2 'uci commit network || {' "$CUSTOM" | grep -c 'STRUCT_FAIL=1')
if [ "$net_commit_guard" -ge 2 ]; then
  ok "两条 network 提交失败路径都置结构性失败($net_commit_guard 处)"
else
  bad "network 提交失败没有置位(只有 $net_commit_guard 处)"
fi

# 单网口随机密码失败必须置位重试, 不能只写 warning 就 exit 0。
# 这是本脚本唯一"失败 = 不安全"的步骤: 退出 0 会让 uci-defaults 删除脚本,
# 设备就永久带着无密码 root 留在上游网段, 且没有第二次机会。
if awk '/count" -eq 1/{f=1} /count" -gt 1/{f=0} f' "$CUSTOM" |
   awk '/lockdown_single_nic_password/{in_blk=1} in_blk && /STRUCT_FAIL=1/{ok=1; exit} END{exit !ok}'; then
  ok "单网口密码设置失败会置结构性失败(下次启动重试)"
else
  bad "单网口密码失败只记 warning 就 exit 0, 设备会永久留在无密码状态"
fi
# 反向: 不能改成"失败也算成功"的空 if
if grep -q 'if ! lockdown_single_nic_password; then' "$CUSTOM"; then
  ok "密码失败走的是失败分支(if ! ...)"
else
  bad "密码调用没有检查返回值"
fi

if grep -q 'pgrep -f nginx' "$CUSTOM"; then
  ok "nginx 启动后校验进程, 不再无条件写成功"
else
  bad "Web 段仍无条件声称配置成功"
fi
if grep -q 'uci -q get uhttpd.main >/dev/null' "$CUSTOM"; then
  ok "uhttpd.main 段缺失时有护栏"
else
  bad "没有检查 uhttpd.main 段, add_list 会静默失败"
fi

# 幂等护栏: 重跑不该把用户改过的东西按回去。
if grep -q 'uhttpd 已在 8080/8443, 跳过端口配置' "$CUSTOM"; then
  ok "uhttpd 端口已达标时跳过重写"
else
  bad "uhttpd 端口每次都被重写, 重跑会冲掉用户自定义"
fi
if grep -q '已是 interface=lan/enable=0' "$CUSTOM"; then
  ok "ttyd 已是目标状态时跳过改配置"
else
  bad "ttyd 配置每次都被重写"
fi
if grep -q 'docker firewall zone 已存在, 跳过重建' "$CUSTOM"; then
  ok "docker zone 已存在时跳过重建(保留用户 forwarding)"
else
  bad "docker forwarding 每次被清空重建"
fi

# 单网口分支要清掉历史遗留的 wan/wan6(比如 eth1 是 USB 网卡时 board.d 会建 wan)。
if awk '/count" -eq 1/{f=1} /count" -gt 1/{f=0} f && /uci -q delete network.wan$/{ok=1} END{exit !ok}' "$CUSTOM"; then
  ok "单网口分支清理 wan/wan6"
else
  bad "单网口分支没有清理 wan, 挂错口的 WAN 会一直 DHCP 重试"
fi

# 变量卫生: 没有拨号输入时 pppoe 变量必须显式初始化, 不靠空串展开。
if grep -q '^enable_pppoe=""$' "$CUSTOM"; then
  ok "pppoe 变量显式初始化"
else
  bad "pppoe 变量未初始化, 依赖未定义变量展开成空串"
fi
if grep -q 'lp_ports=' "$CUSTOM" && ! grep -q '^    ports=""$' "$CUSTOM"; then
  ok "枚举函数用 lp_ 前缀变量(不与主流程撞名)"
else
  bad "枚举函数仍占用通用变量名 ports"
fi

# 日志阶段: 首启日志要能看出卡在哪一步。
stages=$(grep -c '^stage "[0-9]/7' "$CUSTOM")
if [ "$stages" -ge 7 ] && grep -q '^stage() {' "$CUSTOM"; then
  ok "日志有 7 个带时间戳的阶段标记"
else
  bad "阶段标记只有 $stages 个, 排查时看不出卡在哪"
fi

# ================================================================
# 6h. wan6: 不覆盖已有配置, PPPoE 下不硬塞
# ================================================================
# 实机上出现过 IPv6 接口重复(LuCI 里一个 wan_6 起不来、一个 wan6 正常)。
# 根因是脚本无条件写 network.wan6=device+dhcpv6, 再在 PPPoE 分支置 none:
# 既覆盖平台/LuCI 已配好的 IPv6, 又在 PPPoE 下留下一个永不 up 的重复条目。
wan6_sets=$(grep -c "uci set network.wan6=interface" "$CUSTOM")
if [ "$wan6_sets" -eq 1 ] && grep -q 'if wants_wan6 "\$wan6_exists" "\$enable_pppoe"' "$CUSTOM"; then
  ok "wan6 只在 wants_wan6 判定为真时才创建"
else
  bad "wan6 仍是无条件创建($wan6_sets 处), 会覆盖已有 IPv6 配置"
fi

if grep -q "network.wan6.proto='none'" "$CUSTOM"; then
  bad "PPPoE 分支仍把 wan6 置 none, 会把 PPPoE 上的 IPv6 关掉"
else
  ok "PPPoE 下不再把 wan6 置 none"
fi

# PPPoE 下必须把 wan.ipv6 交回 auto, 否则平台不会建动态 wan_6, 而脚本又不建
# UCI wan6 → 整机没有 IPv6 客户端(实机 VM301 复现)。
if awk '/PPPoE enabled, configuring/{f=1} /PPPoE config done/{f=0} f && /uci -q delete network.wan.ipv6/{ok=1} END{exit !ok}' "$CUSTOM"; then
  ok "PPPoE 分支删除 wan.ipv6, 交回 auto(保证 platform 建 wan_6)"
else
  bad "PPPoE 分支没处理 wan.ipv6; 若上游设成 1 就不会有 wan_6, 也没 UCI wan6"
fi
if grep -q 'uci -q get network.wan6 >/dev/null' "$CUSTOM"; then
  ok "创建前先探测 wan6 是否已存在"
else
  bad "没有探测已有 wan6, 会重复配置"
fi

if grep -q '与自动创建的 wan_6 重复' "$CUSTOM"; then
  ok "PPPoE 下已有 wan6 时会在日志提示重复(不擅自删除)"
else
  bad "PPPoE 下残留的 UCI wan6 没有提示, 用户会一直看到两个 IPv6 条目"
fi
if grep -q 'uci -q delete network.wan6' "$CUSTOM" && awk '/count" -gt 1/{f=1} /^fi$/{if(f)f=0} f && /delete network.wan6$/{print; exit}' "$CUSTOM" | grep -q .; then
  bad "多网口/PPPoE 分支擅自删除了 wan6, 会冲掉用户配置"
else
  ok "不擅自删除用户的 wan6"
fi

wan6_src=$(sed -n '/^# >>> wan6-autoconfig/,/^# <<< wan6-autoconfig/p' "$CUSTOM")
if [ -n "$wan6_src" ]; then
  eval "$wan6_src"
  if wants_wan6 0 no && ! wants_wan6 1 no && ! wants_wan6 0 yes && ! wants_wan6 1 yes; then
    ok "wants_wan6: 仅『无 wan6 且非 PPPoE』为真"
  else
    bad "wants_wan6 判定矩阵不对"
  fi
else
  bad "抽不到 wants_wan6, 无法做行为测试"
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
