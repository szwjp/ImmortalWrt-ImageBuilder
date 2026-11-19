#!/bin/sh
# 99-custom.sh 就是immortalwrt固件首次启动时运行的脚本 位于固件内的/etc/uci-defaults/99-custom.sh
# Log file for debugging
# 日志不要写进 /etc/config: 那里只应放 UCI 配置文件。往里塞 .txt 会让无参
# "uci show" 解析整个目录时报 Parse error, 也容易被当配置备份/恢复。
LOGFILE="/tmp/99-custom.log"
echo "Starting 99-custom.sh at $(date)" >>"$LOGFILE"

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
    root_hash=$(awk -F: '$1 == "root" { print $2; exit }' /etc/shadow 2>/dev/null)
    if [ -n "$root_hash" ]; then
        echo "single-nic: root 已有密码, 不生成随机密码" >>"$LOGFILE"
        return 0
    fi

    pw=$(gen_first_boot_password)
    # 生成失败宁可不设, 也不要写出空密码; 失败路径留在日志里。
    if [ "${#pw}" -ne 16 ]; then
        echo "error: 随机密码生成失败(长度 ${#pw})" >>"$LOGFILE"
        return 1
    fi

    # busybox passwd 从标准输入连读两遍; 不用 echo -e, 免得密码被当转义序列处理。
    if ! printf '%s\n%s\n' "$pw" "$pw" | passwd root >/dev/null 2>&1; then
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
    msg="
============================================================
 单网口首次启动: 已生成随机 root 密码
   密码: $pw
 登录: http://<本机从上游 DHCP 得到的地址>/   (LuCI)
       ssh root@<同一地址>
 密码副本: /root/.first-boot-password (仅 root 可读)
 登录后请立即在 [系统 - 管理权] 修改密码, 并删除该文件。
============================================================"
    printf '%s\n' "$msg" >/dev/console 2>/dev/null ||
        printf '%s\n' "$msg" >/dev/tty1 2>/dev/null || true

    mkdir -p /root
    ( umask 077; printf '%s\n' "$pw" > /root/.first-boot-password ) 2>/dev/null ||
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

# 检查配置文件pppoe-settings是否存在 该文件由build.sh动态生成
SETTINGS_FILE="/etc/config/pppoe-settings"
# 构建期由 workflow 塞进 /etc/config 的管理地址(仅多网口用), 读完要删
IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
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

# 1. 先获取所有物理接口列表
# 目录参数只给测试用(测试建一棵假的 sysfs 树), 固件里永远走默认路径。
# >>> list-physical-ports
list_physical_ports() {
    net_dir="${1:-/sys/class/net}"
    ports=""
    for iface in "$net_dir"/*; do
        name=$(basename "$iface")
        # 有 device 节点的才是物理口: 排除 lo、br-lan、veth、docker0 之类虚拟口
        [ -e "$iface/device" ] || continue
        case "$name" in
            eth*|en*) ports="$ports $name" ;;
        esac
    done
    printf '%s\n' "$ports" | awk '{$1=$1};1'
}
# <<< list-physical-ports

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

# 支持上限。为什么是 9: 枚举依赖 /sys/class/net/* 的 glob, 那是字典序,
# 从第 10 个口开始 eth10 会排在 eth2 前面, "最后一个口当 WAN" 必然配错,
# 而且不报错。9 口以内 ethN 的字典序恰好等于数字序, 这条规则才站得住。
# 超限就不做自动映射, 保住镜像默认配置(lan=eth0、wan=eth1), 其余口留给用户
# 在 LuCI 里手工指定 —— 宁可少配, 不写出一个静默错配的 WAN。
MAX_PORTS=9

# 2. 映射WAN和LAN接口
#    /etc/board.json 不在镜像里, 而是首次启动时由 /etc/board.d/* 生成,
#    所以 board_name 是真实板型(例如 x86 上的具体设备型号), 不是 unknown。
#    这里只把它写进日志便于排查, 不按板型做特判 —— 统一按
#    "最后一个网口为WAN, 其余为LAN" 处理, 避免为单一设备形态定制。
board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
echo "Board detected: $board_name" >>$LOGFILE

# 3. 配置网络
if [ "$count" -gt "$MAX_PORTS" ]; then
    # 超限: 不动 network, 也不猜哪个口是 WAN。日志写清楚让用户手工配。
    echo "error: 检测到 $count 个物理网口, 超过自动映射上限 $MAX_PORTS, 跳过网口自动配置(保留镜像默认: lan=eth0、wan=eth1, 其余口请在 LuCI 手工指定)" >>"$LOGFILE"
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
    uci commit network || {
        echo "error: uci commit network failed" >>$LOGFILE
    }

    lockdown_single_nic_password ||
        echo "warning: 随机密码设置失败, root 仍无密码, 本机请勿接入不可信网络" >>"$LOGFILE"
elif [ "$count" -gt 1 ]; then
    # 默认最后一个接口为WAN，其余为LAN
    wan_ifname=$(echo "$ifnames" | awk -v total="$count" '{print $total}')
    lan_ifnames=$(echo "$ifnames" | awk -v total="$count" '{for(i=1;i<total;i++) printf "%s ", $i; if(total>1) printf "\n"}' | sed 's/[[:space:]]*$//')
    echo "Using last interface as WAN mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>"$LOGFILE"

    # 多网口设备配置
    # 配置WAN
    uci set network.wan=interface
    uci set network.wan.device="$wan_ifname"
    uci set network.wan.proto='dhcp'

    # 配置WAN6
    uci set network.wan6=interface
    uci set network.wan6.device="$wan_ifname"
    uci set network.wan6.proto='dhcpv6'

    # 查找 br-lan 设备 section
    section=$(uci show network | awk -F '[.=]' '/\.@?device\[[0-9]+\]\.name=.br-lan.$/ {print $2; exit}')
    if [ -z "$section" ]; then
        echo "error: cannot find device 'br-lan', LAN ports not configured" >>$LOGFILE
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
        uci set network.wan.proto='pppoe'
        uci set network.wan.username="$pppoe_account"
        uci set network.wan.password="$pppoe_password"
        uci set network.wan.peerdns='1'
        uci set network.wan.auto='1'
        uci set network.wan6.proto='none'
        echo "PPPoE config done." >>$LOGFILE
    else
        echo "PPPoE not enabled." >>$LOGFILE
    fi

    uci commit network || {
        echo "error: uci commit network failed" >>$LOGFILE
    }
fi

# custom_router_ip.txt 只是构建期塞进 /etc/config 的一次性输入, 无论走哪个
# 分支都在这里清掉: 留在设备上既是垃圾文件, 也会让无参 "uci show" 扫目录时
# 多一个非 UCI 文件。注意必须在上面读取之后。
rm -f "$IP_VALUE_FILE"

# 管理面收回到 lan: 原来把 dropbear 的 Interface 置空、删掉 ttyd 的 interface,
# 等于所有网口(含 WAN)都能连; 多网口时只剩防火墙一道防线, 规则一改就全开。
# ttyd 是免密网页 shell, 暴露面最大, 这里默认关闭, 需要时用户自己在 LuCI 开启。
if [ -f /etc/config/dropbear ]; then
    uci -q set dropbear.@dropbear[0].Interface='lan'
    echo "dropbear: Interface=lan" >>"$LOGFILE"
fi
if [ -x /etc/init.d/ttyd ]; then
    uci -q set ttyd.@ttyd[0].interface='lan'
    # enable 选项是 luci-app-ttyd 的开关; 连同服务自启一起关掉, 两条路都堵上
    uci -q set ttyd.@ttyd[0].enable='0'
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
if [ -x /etc/init.d/nginx ] && [ -x /etc/init.d/uhttpd ]; then
    echo "Configuring web servers: nginx(80/443) + uhttpd(8080/8443)" >>$LOGFILE

    # uhttpd 监听端口改为 8080/8443。
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

    # 启动顺序: 先起 nginx 占用 80/443, 再起 uhttpd。
    # 若顺序反了, uhttpd 会先绑上 80 导致 nginx bind 失败。
    /etc/init.d/nginx enable
    /etc/init.d/uwsgi enable
    /etc/init.d/uhttpd enable

    # uhttpd 需要自签证书才能起 HTTPS(8443), 证书由 uhttpd 的 cert 段生成
    /etc/init.d/uhttpd start >/dev/null 2>&1
    /etc/init.d/uwsgi start >/dev/null 2>&1
    /etc/init.d/nginx start >/dev/null 2>&1

    echo "Web servers configured, nginx:80/443, uhttpd:8080/8443" >>$LOGFILE
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
FILE_PATH="/etc/openwrt_release"
PACKAGER_SUFFIX=" (Packaged by szwjp)"
if [ -f "$FILE_PATH" ]; then
    sed -i "s/^\(DISTRIB_DESCRIPTION='\)\([^']*\)'\$/\1\2${PACKAGER_SUFFIX}'/" "$FILE_PATH"
fi

# 若安装了dockerd 则设置docker的防火墙规则
# 扩大docker涵盖的子网范围 '172.16.0.0/12'
# 方便各类docker容器的端口顺利通过防火墙
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..."

    # 删除所有名为 docker 的 zone
    uci -q delete firewall.docker

    # 删除所有引用 docker zone 的 forwarding。
    # 用 section 标识(@forwarding[N] 或具名段)而不是数组下标: 具名段
    # (config forwarding 'xxx') 取不到数字下标, 老写法会漏删。
    for sek in $(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=forwarding$/\1/p'); do
        src=$(uci -q get "firewall.$sek.src")
        dest=$(uci -q get "firewall.$sek.dest")
        echo "Checking forwarding $sek: src=$src dest=$dest"
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            echo "Deleting forwarding $sek"
            uci -q delete "firewall.$sek"
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

else
    echo "未检测到 Docker，跳过防火墙配置。"
fi

exit 0
