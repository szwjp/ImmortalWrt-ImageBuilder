#!/bin/sh
# 99-custom.sh 就是immortalwrt固件首次启动时运行的脚本 位于固件内的/etc/uci-defaults/99-custom.sh
# Log file for debugging
# 日志不要写进 /etc/config: 那里只应放 UCI 配置文件。往里塞 .txt 会让无参
# "uci show" 解析整个目录时报 Parse error, 也容易被当配置备份/恢复。
LOGFILE="/tmp/99-custom.log"
echo "Starting 99-custom.sh at $(date)" >>"$LOGFILE"

# 分阶段打点: 首启日志要能看出"卡在哪一步", 时间戳也让重试间隔可读。
stage() { printf '=== [%s] %s ===\n' "$(date '+%H:%M:%S')" "$*" >>"$LOGFILE"; }

# 结构性失败(找不到 br-lan、network 写盘失败)才返回非 0:
# uci-defaults 只在退出 0 时删除脚本, 非 0 会被保留、下次启动重试。
# 环境差异(没装 ttyd/nginx、uhttpd 段异常)不置位 —— 那些重试也没用,
# 反而会把用户在 LuCI 里的改动冲掉。
STRUCT_FAIL=0

# 管理地址校验的唯一实现: 构建时由 build.sh 从 shell/validate-ip.sh 拷到
# /usr/lib/imm/validate-ip.sh。本脚本只 source, 不再内联正则 —— 以前
# workflow 与这里各写一份, 规则一改就漂移。
IP_LIB="/usr/lib/imm/validate-ip.sh"
if [ -r "$IP_LIB" ]; then
    # shellcheck disable=SC1090  # 固件内固定路径, 本地不存在属正常
    . "$IP_LIB"
else
    echo "warning: $IP_LIB 不存在, 管理地址将退回默认值" >>"$LOGFILE"
fi

# ============ 单网口首启: 随机 root 密码 ============
# 单网口设备(DHCP 模式)的唯一网口属于 lan zone, 设备会成为上游局域网的一员,
# 同网段任何主机都能直连 22/443。固件默认 root 无密码: 在多网口设备上这只
# 暴露在自有 LAN 内, 在单网口上等于把管理权公开给上游网络。所以单网口首启
# 生成一次性随机密码, 打印到本机控制台, 并落一份仅 root 可读的副本。
# 多网口不动: LAN 是独立网段, 保持开箱即用。
#
# 该函数被 shell/tests/firmware-config-test.sh 按标记整段抽出做行为测试,
# 标记行本身别改。
# >>> first-boot-password
gen_first_boot_password() {
    # 去掉 0/O/1/l/I/o 等易混字符: 这是要照着控制台手敲的密码。
    # LC_ALL=C 保证不同 locale 下字符集一致。
    LC_ALL=C tr -dc 'A-HJ-NP-Za-km-np-z2-9' < /dev/urandom 2>/dev/null | head -c 16
}
# <<< first-boot-password

lockdown_single_nic_password() {
    # 已经有密码就不动: 脚本可能被手动重跑, 不能每次启动都换密码。
    nic_root_hash=$(awk -F: '$1 == "root" { print $2; exit }' /etc/shadow 2>/dev/null)
    if [ -n "$nic_root_hash" ]; then
        echo "single-nic: root 已有密码, 不生成随机密码" >>"$LOGFILE"
        return 0
    fi

    nic_pw=$(gen_first_boot_password)
    # 生成失败宁可不设, 也不要写出空密码; 失败路径留在日志里。
    if [ "${#nic_pw}" -ne 16 ]; then
        echo "error: 随机密码生成失败(长度 ${#nic_pw})" >>"$LOGFILE"
        return 1
    fi

    # busybox passwd 从标准输入连读两遍; 不用 echo -e, 免得密码被当转义序列处理。
    if ! printf '%s\n%s\n' "$nic_pw" "$nic_pw" | passwd root >/dev/null 2>&1; then
        echo "error: passwd 设置 root 密码失败" >>"$LOGFILE"
        return 1
    fi
    # passwd 返回 0 不等于真写进去了(比如 shadow 只读), 回读确认。
    if [ -z "$(awk -F: '$1 == "root" { print $2; exit }' /etc/shadow 2>/dev/null)" ]; then
        echo "error: passwd 返回成功但 /etc/shadow 里 root 仍无密码" >>"$LOGFILE"
        return 1
    fi
    # 日志里绝不出现密码本身: /tmp/99-custom.log 会被回传给排查者。
    echo "single-nic: 已生成随机 root 密码(值不写日志)" >>"$LOGFILE"

    # 控制台是取密码的唯一通道。x86 上 /dev/console 通常是 tty0(接显示器),
    # 服务器/虚拟机是串口; 写不进去时退回 /dev/tty1。
    nic_msg="
============================================================
 单网口首次启动: 已生成随机 root 密码
   密码: $nic_pw
 登录: http://<本机从上游 DHCP 得到的地址>/   (LuCI)
       ssh root@<同一地址>
 密码副本: /root/.first-boot-password (仅 root 可读)
 登录后请立即在 [系统 - 管理权] 修改密码, 并删除该文件。
============================================================"
    printf '%s\n' "$nic_msg" >/dev/console 2>/dev/null ||
        printf '%s\n' "$nic_msg" >/dev/tty1 2>/dev/null || true

    mkdir -p /root
    ( umask 077; printf '%s\n' "$nic_pw" > /root/.first-boot-password ) 2>/dev/null ||
        echo "warning: 无法写入 /root/.first-boot-password" >>"$LOGFILE"
    chmod 600 /root/.first-boot-password 2>/dev/null

    # banner 只写"密码在哪", 不写密码: 它是 dropbear 登录前的提示,
    # 未认证的人也能看到。
    if ! grep -q '单网口首次启动已生成随机 root 密码' /etc/banner 2>/dev/null; then
        {
            echo ""
            echo "*** 单网口首次启动已生成随机 root 密码。"
            echo "*** 密码见设备本机控制台输出, 或登录后 cat /root/.first-boot-password。"
            echo ""
        } >> /etc/banner 2>/dev/null
    fi
    return 0
}

# 刻意不改 firewall 的 zone 入站策略。
#
# 单网口设备的唯一网口在默认配置里属于 lan zone: /etc/board.d/99-default_network
# 固定把 eth0 映射成 lan, 只有 eth1 存在时才建 wan。lan zone 默认 input ACCEPT,
# 首访 WebUI 本来就能通。给 wan zone 开 ACCEPT 既没有实际作用, 又会在以后有人
# 添加 wan 接口时白送一个入站放行, 所以这里不做。

stage "1/7 读取构建期输入"
# 检查配置文件pppoe-settings是否存在 该文件由build.sh动态生成
SETTINGS_FILE="/etc/config/pppoe-settings"
# 构建期由 workflow 塞进 /etc/config 的管理地址(仅多网口用), 读完要删
IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
# 显式初始化: 没有拨号输入时这些变量为空, 后面的判断据此走"未启用"分支,
# 而不是依赖未定义变量展开成空串(哪天加了 set -u 也不会炸)。
enable_pppoe=""
pppoe_account=""
pppoe_password=""
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >>$LOGFILE
else
    # 读取pppoe信息($enable_pppoe、$pppoe_account、$pppoe_password)
    # 用 uci get 读, 不用 . (source): source 会把文件内容当 shell 代码解析,
    # 密码里的 $ ' " ; 等字符会被展开或当成命令, 导致密码被静默篡改甚至注入命令。
    # build.sh 那边按 UCI 双引号格式写, 这里由 uci 负责取值。
    enable_pppoe=$(uci -q get pppoe-settings.pppoe.enabled)
    pppoe_account=$(uci -q get pppoe-settings.pppoe.account)
    pppoe_password=$(uci -q get pppoe-settings.pppoe.password)
    # 含明文密码，读取后立即删除
    rm -f "$SETTINGS_FILE"
fi

stage "2/7 枚举物理网口"
# 1. 先获取所有物理接口列表
# 目录参数只给测试用(测试建一棵假的 sysfs 树), 固件里永远走默认路径。
# >>> list-physical-ports
# shellcheck disable=SC2120  # 目录参数只给测试用, 固件里的调用永远不带参
list_physical_ports() {
    # 变量统一加 lp_ 前缀: POSIX sh 没有可靠的 local, 别和主流程的变量撞名。
    lp_dir="${1:-/sys/class/net}"
    lp_ports=""
    for lp_iface in "$lp_dir"/*; do
        lp_name=$(basename "$lp_iface")
        # 有 device 节点的才是物理口: 排除 lo、br-lan、veth、docker0 之类虚拟口
        [ -e "$lp_iface/device" ] || continue
        # eth/en 是内核默认命名; lan/wan 是部分固件改过的命名, 一并收下。
        case "$lp_name" in
            eth*|en*|lan*|wan*) lp_ports="$lp_ports $lp_name" ;;
        esac
    done
    printf '%s\n' "$lp_ports" | awk '{$1=$1};1'
}
# <<< list-physical-ports

# 从 `uci show network` 的输出里取 br-lan 的 device 段名。
# 必须按值匹配, 不能只认 @device[N]: 段一旦被命名过(config device 'brlan'),
# 老写法就找不到, 于是端口不重排、LAN 也不设地址, 而脚本照样 exit 0。
# >>> brlan-section
find_brlan_section() {
    sed -n -e "s/^network\.\([^.=]*\)\.name='br-lan'\$/\1/p" \
           -e "s/^network\.\([^.=]*\)\.name=br-lan\$/\1/p" | head -1
}
# <<< brlan-section

# 是否要自动补 wan6: 只在「镜像里还没有 wan6」且「WAN 不是 PPPoE」时补。
# 为什么 PPPoE 下不能补: PPP 链路起来后 /lib/netifd/ppp6-up 会自己用
#   ubus call network add_dynamic 建一个名为 ${wan}_6 的动态 DHCPv6 客户端
# (实测: ifstatus wan_6 -> dynamic:true, proto:dhcpv6, device:pppoe-wan)。
# 它不在任何 UCI 配置文件里, 所以 uci show network 看不到; 此时再写一个 UCI
# wan6, LuCI 里就会出现两个 IPv6 条目(wan_6 + wan6) —— 这正是实机反馈的现象。
# 另外无条件 uci set 还会覆盖用户已配好的 wan6, 所以已有就一律不动。
# >>> wan6-autoconfig
wants_wan6() {
    # $1: 已有 wan6 则为 1; $2: enable_pppoe 的值
    [ "$1" != "1" ] && [ "$2" != "yes" ]
}
# <<< wan6-autoconfig

ifnames=$(list_physical_ports)
count=$(echo "$ifnames" | wc -w)
echo "Detected physical interfaces: $ifnames" >>$LOGFILE
echo "Interface count: $count" >>$LOGFILE

# 每个口的 MAC/驱动/PCI 路径都记进日志: 网口顺序错了、WAN 落到不认识的口上时,
# 用户能据此判断是硬件对不上还是脚本判错, 不用靠猜。
for port in $ifnames; do
    mac=$(cat "/sys/class/net/$port/address" 2>/dev/null)
    driver=$(basename "$(readlink -f "/sys/class/net/$port/device/driver" 2>/dev/null)")
    pci=$(basename "$(readlink -f "/sys/class/net/$port/device" 2>/dev/null)")
    echo "port $port: mac=$mac driver=$driver pci=$pci" >>$LOGFILE
done

# 支持上限。枚举依赖 /sys/class/net/* 的 glob, 那是字典序: 名字里一旦出现
# 两位数(eth10), eth10 会排在 eth2 前面, "最后一个口当 WAN" 就配错,
# 而且不报错。实测 10 口(eth0..eth9)排序仍然正确, 错位从第 11 口开始。
# 这里仍取 9 而不是 10: 多留一档余量, 让"上限"与"实际开始出错"之间有
# 间隔, 避免以后有人改命名规则(比如去掉 eth0)时刚好踩线。
# 超限就不做自动映射, 保留镜像默认网络配置, 其余口留给用户在 LuCI 里
# 手工指定 —— 宁可少配, 不写出一个静默错配的 WAN。
MAX_PORTS=9

# 2. 映射WAN和LAN接口
#    /etc/board.json 不在镜像里, 而是首次启动时由 /etc/board.d/* 生成,
#    所以 board_name 是真实板型(例如 x86 上的具体设备型号), 不是 unknown。
#    这里只把它写进日志便于排查, 不按板型做特判 —— 统一按
#    "最后一个网口为WAN, 其余为LAN" 处理, 避免为单一设备形态定制。
board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
echo "Board detected: $board_name" >>$LOGFILE

# 3. 配置网络
stage "3/7 配置网络 (count=$count)"
if [ "$count" -gt "$MAX_PORTS" ]; then
    # 超限: 不动 network, 也不猜哪个口是 WAN。日志写清楚让用户手工配。
    echo "error: 检测到 $count 个物理网口, 超过自动映射上限 $MAX_PORTS, 跳过网口自动配置(保留镜像默认网络配置: 通常 lan=br-lan 含 eth0, wan 取决于存在哪些网口; 其余口请在 LuCI 手工指定)" >>"$LOGFILE"
elif [ "$count" -eq 1 ]; then
    # 单网口设备，DHCP模式。唯一网口属于 lan zone(默认入站放行), 无需动防火墙。
    # 但这也意味着设备会直接接入上游局域网: 管理面就在那一侧, 所以下面必须
    # 先把 root 密码设上, 不能让"默认无密码"的状态活在别人的网段里。
    # 顺序也重要: uci-defaults 在 S10boot 阶段执行, 早于 S20network 起网络,
    # 所以密码先于网口可用就位。
    echo "single-nic: DHCP 模式, 设备将接入上游局域网, 随后生成随机 root 密码" >>"$LOGFILE"
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr
    uci delete network.lan.netmask
    uci delete network.lan.gateway
    uci delete network.lan.dns
    # 单网口机器本来不该有 WAN; 但 board.d 只在 eth1 存在时才建 wan,
    # 而 eth1 可能是 USB 网卡/虚拟口。留着一个挂错口的 wan 会让它反复 DHCP 重试,
    # LuCI 里也会多出一个永远起不来的接口, 所以这里清掉。
    uci -q delete network.wan
    uci -q delete network.wan6
    uci commit network || {
        echo "error: uci commit network failed" >>$LOGFILE
        STRUCT_FAIL=1
    }

    lockdown_single_nic_password ||
        echo "warning: 随机密码设置失败, root 仍无密码, 本机请勿接入不可信网络" >>"$LOGFILE"
elif [ "$count" -gt 1 ]; then
    # 默认最后一个接口为WAN，其余为LAN
    wan_ifname=$(echo "$ifnames" | awk -v total="$count" '{print $total}')
    lan_ifnames=$(echo "$ifnames" | awk -v total="$count" '{for(i=1;i<total;i++) printf "%s ", $i; if(total>1) printf "\n"}' | sed 's/[[:space:]]*$//')
    echo "Using last interface as WAN mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>"$LOGFILE"

    # 多网口设备配置
    # 配置WAN。
    # 假定 WAN 段名就是 wan(镜像默认如此); 若上游改成别的段名, 这里会新建一段,
    # 旧段会留在配置里, 由用户在 LuCI 手工清理 —— 首启阶段无法可靠猜测别名。
    uci set network.wan=interface
    uci set network.wan.device="$wan_ifname"
    uci set network.wan.proto='dhcp'

    # 配置WAN6: 已有配置不动, 启用 PPPoE 时也不补(理由见 wants_wan6 的注释)
    if uci -q get network.wan6 >/dev/null 2>&1; then
        wan6_exists=1
    else
        wan6_exists=0
    fi
    if wants_wan6 "$wan6_exists" "$enable_pppoe"; then
        uci set network.wan6=interface
        uci set network.wan6.device="$wan_ifname"
        uci set network.wan6.proto='dhcpv6'
        echo "wan6: 新建 DHCPv6 客户端($wan_ifname)" >>"$LOGFILE"
    else
        if [ "$enable_pppoe" = "yes" ]; then
            echo "wan6: PPPoE 模式, 不自动创建(IPv6 由 ppp6-up 自动创建的 wan_6 负责)" >>"$LOGFILE"
            # 升级上来的机器可能带着旧固件写下的 UCI wan6; 不自动删(可能是用户自己的
            # 配置), 但必须提示, 否则 LuCI 里会一直是两个 IPv6 条目。
            if [ "$wan6_exists" = "1" ]; then
                echo "warning: PPPoE 模式下还有 UCI wan6, 与自动创建的 wan_6 重复, 建议在 LuCI【网络 - 接口】删除 wan6" >>"$LOGFILE"
            fi
        else
            echo "wan6: 已有 UCI 配置, 保持不变" >>"$LOGFILE"
        fi
    fi

    # 查找 br-lan 设备 section(按段名值匹配, 具名段也能找到)
    section=$(uci show network | find_brlan_section)
    if [ -z "$section" ]; then
        echo "error: cannot find device 'br-lan', LAN ports not configured" >>$LOGFILE
        STRUCT_FAIL=1
    else
        # 删除原有ports
        uci -q delete "network.$section.ports"
        # 添加LAN接口端口
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports"="$port"
        done
        # 开启 STP 防止多 LAN 口接入同一交换机时产生环路
        uci set "network.$section.stp"='1'
        echo "Updated br-lan ports: $lan_ifnames" >>$LOGFILE

        # LAN口设置静态IP (仅在 br-lan 找到时配置，避免写出半残配置)
        uci set network.lan.proto='static'
        # 多网口设备 支持修改为别的管理后台地址 在Github Action 的UI上自行输入即可
        uci set network.lan.netmask='255.255.255.0'
        # 设置路由器管理后台地址
        if [ -f "$IP_VALUE_FILE" ]; then
            CUSTOM_IP=$(cat "$IP_VALUE_FILE")
            # 规则在 /usr/lib/imm/validate-ip.sh: 除了每段 0-255, 还拒绝
            # 0.0.0.0、网络/广播地址(.0/.255)、回环、组播、169.254/16。
            if ip_is_usable "$CUSTOM_IP" 2>/dev/null; then
                # 用户在UI上设置的路由器后台管理地址
                uci set network.lan.ipaddr="$CUSTOM_IP"
                echo "custom router ip is $CUSTOM_IP" >> $LOGFILE
            else
                uci set network.lan.ipaddr='192.168.1.1'
                echo "invalid custom router ip '$CUSTOM_IP', fallback to 192.168.1.1" >> $LOGFILE
            fi
        else
            uci set network.lan.ipaddr='192.168.1.1'
            echo "default router ip is 192.168.1.1" >> $LOGFILE
        fi
    fi

    # PPPoE设置 (只影响WAN口，不依赖LAN配置)
    echo "enable_pppoe value: $enable_pppoe" >>$LOGFILE
    if [ "$enable_pppoe" = "yes" ]; then
        echo "PPPoE enabled, configuring..." >>$LOGFILE
        # 平台的自动 IPv6 客户端(wan_6) 依赖 ppp.sh 的 autoipv6 分支: 只有
        # wan.ipv6 未设置或为 auto 时 ppp6-up 才会 add_dynamic 建 wan_6。
        # 一旦上游把它显式写成 1, 就不会有 wan_6, 而我们又不再建 UCI wan6 ——
        # 那台机器会完全没有 IPv6 客户端(实机 VM301 复现过)。这里删掉该选项,
        # 把选择权交回平台的 auto 行为。
        uci -q delete network.wan.ipv6
        uci set network.wan.proto='pppoe'
        uci set network.wan.username="$pppoe_account"
        uci set network.wan.password="$pppoe_password"
        uci set network.wan.peerdns='1'
        uci set network.wan.auto='1'
        # 不再把 wan6 置 none: PPPoE 链路本身承载 IPv6, 平台/LuCI 会把 wan6 的
        # device 指向 pppoe-wan; 这里写死 none 会把 IPv6 关掉。
        echo "PPPoE config done." >>$LOGFILE
    else
        echo "PPPoE not enabled." >>$LOGFILE
    fi

    uci commit network || {
        echo "error: uci commit network failed" >>$LOGFILE
        STRUCT_FAIL=1
    }
fi

# custom_router_ip.txt 只是构建期塞进 /etc/config 的一次性输入, 无论走哪个
# 分支都在这里清掉: 留在设备上既是垃圾文件, 也会让无参 "uci show" 扫目录时
# 多一个非 UCI 文件。注意必须在上面读取之后。
rm -f "$IP_VALUE_FILE"

# 管理面收回到 lan: 原来把 dropbear 的 Interface 置空、删掉 ttyd 的 interface,
# 等于所有网口(含 WAN)都能连; 多网口时只剩防火墙一道防线, 规则一改就全开。
# ttyd 是免密网页 shell, 暴露面最大, 这里默认关闭, 需要时用户自己在 LuCI 开启。
stage "4/7 收拢管理面(dropbear/ttyd/banner)"
if [ -f /etc/config/dropbear ]; then
    uci -q set dropbear.@dropbear[0].Interface='lan'
    echo "dropbear: Interface=lan" >>"$LOGFILE"
fi
if [ -x /etc/init.d/ttyd ]; then
    # 幂等: 已经是 interface=lan + enable=0 就不再改配置, 免得重跑脚本
    # 把用户在 LuCI 里调过的值又按回去。
    if [ "$(uci -q get ttyd.@ttyd[0].interface)" = "lan" ] &&
       [ "$(uci -q get ttyd.@ttyd[0].enable)" = "0" ]; then
        echo "ttyd: 已是 interface=lan/enable=0, 跳过改配置" >>"$LOGFILE"
    else
        uci -q set ttyd.@ttyd[0].interface='lan'
        # enable 选项是 luci-app-ttyd 的开关; 连同服务自启一起关掉, 两条路都堵上
        uci -q set ttyd.@ttyd[0].enable='0'
    fi
    /etc/init.d/ttyd stop >/dev/null 2>&1
    /etc/init.d/ttyd disable >/dev/null 2>&1
    echo "ttyd: interface=lan, 默认关闭(需要时在 LuCI 手动开启)" >>"$LOGFILE"
fi

# root 无密码时, 在登录 banner 上明说 —— 默认状态不该被当成安全状态。
# 加去重判断: 脚本被手动重跑时不要把同一段提示叠很多遍。
ROOT_HASH=$(awk -F: '$1 == "root" { print $2; exit }' /etc/shadow 2>/dev/null)
if [ -z "$ROOT_HASH" ] && ! grep -q '安全提示: root 当前没有密码' /etc/banner 2>/dev/null; then
    {
        echo ""
        echo "*** 安全提示: root 当前没有密码。"
        echo "*** 登录 LuCI 后请立即在 [系统 - 管理权] 设置密码;"
        echo "*** 在此之前不要把本机接入不可信网络。"
        echo "*** 网页终端(ttyd)已默认关闭, 需要时在 LuCI 中手动开启。"
        echo "*** (设置密码后本段提示可忽略)"
        echo ""
    } >> /etc/banner
    echo "warning: root 无密码, 已在 /etc/banner 提示" >>"$LOGFILE"
fi

# ============ Web 服务器: nginx 主(80/443) + uhttpd 辅(8080/8443) ============
# nginx-mod-luci 自带的 /etc/uci-defaults/60_nginx-luci-support 会执行
# "uhttpd disable" 并把 uhttpd 停掉, 把 80/443 独占给 nginx。
# 本固件要保留 uhttpd 作为辅助 Web 服务器(备用入口), 所以这里把 uhttpd
# 重新拉起来并改到 8080/8443, 让 80/443 完整归 nginx。
#
# 执行顺序: 60_nginx-luci-support 先跑, 99-custom.sh 后跑, 所以这里的设置
# 会覆盖 60 里的 disable/stop。
stage "5/7 编排 Web 服务器"
if [ -x /etc/init.d/nginx ] && [ -x /etc/init.d/uhttpd ]; then
    echo "Configuring web servers: nginx(80/443) + uhttpd(8080/8443)" >>$LOGFILE

    # 先确认 uhttpd 的 main 段存在: 段名对不上时 add_list 会静默失败,
    # uhttpd 仍占着 80/443, nginx 就绑不上 —— 那种情况下至少日志里说清楚。
    if ! uci -q get uhttpd.main >/dev/null 2>&1; then
        echo "error: /etc/config/uhttpd 缺少 main 段, uhttpd 端口未调整, 80/443 可能与 nginx 冲突" >>"$LOGFILE"
    elif uci -q get uhttpd.main.listen_http | grep -q ':8080' &&
         uci -q get uhttpd.main.listen_https | grep -q ':8443'; then
        # 幂等: 已经在目标端口上就不再重写配置, 免得重跑脚本冲掉用户改过的监听。
        echo "uhttpd 已在 8080/8443, 跳过端口配置" >>"$LOGFILE"
    else
        # listen_http/listen_https 是 list 类型, 多个地址要 add_list 逐条加,
        # 不能用 uci set 一次塞两个值(带空格的引号会被 uci 解析器当成整体)。
        uci -q delete uhttpd.main.listen_http
        uci -q delete uhttpd.main.listen_https
        uci add_list uhttpd.main.listen_http='0.0.0.0:8080'
        uci add_list uhttpd.main.listen_http='[::]:8080'
        uci add_list uhttpd.main.listen_https='0.0.0.0:8443'
        uci add_list uhttpd.main.listen_https='[::]:8443'

        # uhttpd 不做 HTTP->HTTPS 跳转: 它已是备用入口, 且 nginx 在 80 上
        # 自行 302 跳 HTTPS, 两者行为保持一致即可。
        uci set uhttpd.main.redirect_https='0'

        uci commit uhttpd
    fi

    # 启动顺序: 先起 nginx 占用 80/443, 再起 uhttpd。
    /etc/init.d/nginx enable
    /etc/init.d/uwsgi enable
    /etc/init.d/uhttpd enable

    # uhttpd 需要自签证书才能起 HTTPS(8443), 没有证书/生成器时只有 HTTP 可用。
    /etc/init.d/uhttpd start >/dev/null 2>&1
    /etc/init.d/uwsgi start >/dev/null 2>&1
    /etc/init.d/nginx start >/dev/null 2>&1

    # 不假设 start 成功: 80/443 是主入口, 起不来必须在日志里留下错误。
    if pgrep -f nginx >/dev/null 2>&1; then
        echo "Web servers configured, nginx:80/443, uhttpd:8080/8443" >>$LOGFILE
    else
        echo "error: nginx 未启动成功, 80/443 不可用(可查 /var/log/nginx 或手动 /etc/init.d/nginx start)" >>"$LOGFILE"
    fi
    if ! pgrep -f uhttpd >/dev/null 2>&1; then
        echo "warning: uhttpd 未运行, 8080/8443 备用入口不可用" >>"$LOGFILE"
    fi
else
    echo "nginx or uhttpd init script not found, skip web server config" >>$LOGFILE
fi

# 显式提交本脚本改动过的包。
# 不用裸 "uci commit"(提交全部包): 那会把其它脚本在同一批次里留下的半成品
# 改动一起写盘。uci commit 一次只能提交一个包(多包会报 usage 错), 所以逐个提交。
# network 包在上面的分支里已单独提交, firewall 已由 docker 段自己提交, 这里不重复。
# 逐个包用 -q: 某个包不存在时(如未装 ttyd)只跳过它, 不刷错误也不中断脚本。
uci -q commit dropbear
uci -q commit ttyd

# 在原有版本描述后追加打包者信息。
# 不能整行替换: DISTRIB_DESCRIPTION 是 LuCI 状态页显示的固件版本行,
# 覆盖成一句署名后, 界面上就看不到版本号了。
# 幂等: 已经加过就跳过 —— 脚本可能被手动重跑, 后缀不该叠成一长串。
# >>> packager-suffix
add_packager_suffix() {
    pkg_file="$1"
    pkg_mark="Packaged by szwjp"
    [ -f "$pkg_file" ] || return 0
    grep -qF "$pkg_mark" "$pkg_file" && return 0
    # 不用 sed -i: busybox 与 BSD sed 的 -i 语义不同(是否跟备份后缀),
    # 先写临时文件再覆盖回去, 两边都能跑, 也保住原文件的权限位。
    pkg_tmp="$pkg_file.tmp.$$"
    sed "s/^\(DISTRIB_DESCRIPTION='\)\([^']*\)'\$/\1\2 (${pkg_mark})'/" "$pkg_file" > "$pkg_tmp" &&
        cat "$pkg_tmp" > "$pkg_file"
    pkg_rc=$?
    rm -f "$pkg_tmp"
    return $pkg_rc
}
# <<< packager-suffix

add_packager_suffix /etc/openwrt_release

# 若安装了 dockerd 则设置 docker 的防火墙规则。
# 扩大 docker 涵盖的子网范围 '172.16.0.0/12', 方便各类 docker 容器端口通过防火墙。
configure_docker_firewall() {
    # 删除所有名为 docker 的 zone
    uci -q delete firewall.docker

    # 删除所有引用 docker zone 的 forwarding。
    # 用 section 标识(@forwarding[N] 或具名段)而不是数组下标: 具名段
    # (config forwarding 'xxx') 取不到数字下标, 老写法会漏删。
    for fw_sek in $(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=forwarding$/\1/p'); do
        fw_src=$(uci -q get "firewall.$fw_sek.src")
        fw_dest=$(uci -q get "firewall.$fw_sek.dest")
        echo "Checking forwarding $fw_sek: src=$fw_src dest=$fw_dest"
        if [ "$fw_src" = "docker" ] || [ "$fw_dest" = "docker" ]; then
            echo "Deleting forwarding $fw_sek"
            uci -q delete "firewall.$fw_sek"
        fi
    done

    # 新增 docker zone。
    # 这里用 uci 命令而不是 cat >> 追加原文: 追加的文本绕过 uci 的校验与规范化,
    # 后续任何 uci commit 都会把它重排改写。uci 写法产出的配置与追加原文等价
    # (zone 具名 'docker', forwarding 为匿名段)。
    uci set firewall.docker=zone
    uci set firewall.docker.name='docker'
    uci set firewall.docker.input='ACCEPT'
    uci set firewall.docker.output='ACCEPT'
    uci set firewall.docker.forward='ACCEPT'
    uci add_list firewall.docker.subnet='172.16.0.0/12'

    # 三条 forwarding: docker->lan, docker->wan, lan->docker
    # uci add 每次新增一个匿名 forwarding 段, 随后用 @forwarding[-1] 定位它
    uci add firewall forwarding >/dev/null
    uci set "firewall.@forwarding[-1].src=docker"
    uci set "firewall.@forwarding[-1].dest=lan"

    uci add firewall forwarding >/dev/null
    uci set "firewall.@forwarding[-1].src=docker"
    uci set "firewall.@forwarding[-1].dest=wan"

    uci add firewall forwarding >/dev/null
    uci set "firewall.@forwarding[-1].src=lan"
    uci set "firewall.@forwarding[-1].dest=docker"

    # 提交所有改动
    uci commit firewall
}

# 幂等: docker zone 已经存在就整体跳过 —— 重跑脚本不该把用户自己加的
# docker forwarding 清掉重建成固定三条。
stage "6/7 Docker 防火墙"
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..."
    if [ "$(uci -q get firewall.docker.name)" = "docker" ]; then
        echo "docker firewall zone 已存在, 跳过重建(保留用户自定义 forwarding)" >>"$LOGFILE"
    else
        configure_docker_firewall
    fi
else
    echo "未检测到 Docker，跳过防火墙配置。"
fi

stage "7/7 收尾"
if [ "$STRUCT_FAIL" -ne 0 ]; then
    # 非 0 退出 = 脚本不会被 boot 删除, 下次启动会重试。只在结构性失败时这么做:
    # 环境差异(没装 ttyd/nginx、uhttpd 段异常)重试也没用, 还会冲掉用户改动。
    echo "error: 存在结构性配置失败, 保留脚本待下次启动重试" >>"$LOGFILE"
fi
exit "$STRUCT_FAIL"
