#!/bin/sh
# 99-custom.sh 就是immortalwrt固件首次启动时运行的脚本 位于固件内的/etc/uci-defaults/99-custom.sh
# Log file for debugging
# 日志不要写进 /etc/config: 那里只应放 UCI 配置文件。往里塞 .txt 会让无参
# "uci show" 解析整个目录时报 Parse error, 也容易被当配置备份/恢复。
LOGFILE="/tmp/99-custom.log"
echo "Starting 99-custom.sh at $(date)" >>"$LOGFILE"

# 找到 firewall 里 name 为 wan 的 zone section。
# 兼容两种写法: 匿名段(config zone + option name 'wan', 输出 @zone[N])
# 与具名段(config zone 'wan', 输出 wan)。老实现只认匿名段。
find_wan_zone() {
    local line sek name
    for line in $(uci show firewall 2>/dev/null | grep -E '^firewall\.[^.=]+=zone$'); do
        sek=${line%%=*}
        sek=${sek#firewall.}
        name=$(uci -q get "firewall.$sek.name")
        [ -n "$name" ] || name="$sek"
        if [ "$name" = "wan" ]; then
            printf '%s' "$sek"
            return 0
        fi
    done
    return 1
}

# 放开 wan zone 的入站。仅在单网口设备调用:
# 单网口没有独立的 LAN 口, 首访 WebUI 只能走这唯一网口, 需要放行;
# 多网口设备用 LAN 静态地址访问, 不该在 WAN 上开洞(保持默认 REJECT)。
open_wan_input() {
    local wan_zone
    if wan_zone=$(find_wan_zone); then
        uci set "firewall.$wan_zone.input=ACCEPT"
        echo "wan zone '$wan_zone' input -> ACCEPT (单网口首访用)" >>"$LOGFILE"
    else
        echo "error: cannot find wan zone in firewall config" >>"$LOGFILE"
    fi
}

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
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        ifnames="$ifnames $iface_name"
    fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')

count=$(echo "$ifnames" | wc -w)
echo "Detected physical interfaces: $ifnames" >>$LOGFILE
echo "Interface count: $count" >>$LOGFILE

# 2. 映射WAN和LAN接口
#    /etc/board.json 不在镜像里, 而是首次启动时由 /etc/board.d/* 生成,
#    所以 board_name 是真实板型(例如 x86 上的具体设备型号), 不是 unknown。
#    这里只把它写进日志便于排查, 不按板型做特判 —— 统一按
#    "最后一个网口为WAN, 其余为LAN" 处理, 避免为单一设备形态定制。
board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
echo "Board detected: $board_name" >>$LOGFILE

wan_ifname=""
lan_ifnames=""
# 默认最后一个接口为WAN，其余为LAN
total_interfaces=$(echo "$ifnames" | wc -w)
wan_ifname=$(echo "$ifnames" | awk -v total="$total_interfaces" '{print $total}')
lan_ifnames=$(echo "$ifnames" | awk -v total="$total_interfaces" '{for(i=1;i<total;i++) printf "%s ", $i; if(total>1) printf "\n"}' | sed 's/[[:space:]]*$//')
echo "Using last interface as WAN mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>"$LOGFILE"

# 3. 配置网络
if [ "$count" -eq 1 ]; then
    # 单网口: 唯一网口既是 LAN 也是 WAN, 首访 WebUI 需要放开入站
    open_wan_input
    # 单网口设备，DHCP模式
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr
    uci delete network.lan.netmask
    uci delete network.lan.gateway
    uci delete network.lan.dns
    uci commit network || {
        echo "error: uci commit network failed" >>$LOGFILE
    }
elif [ "$count" -gt 1 ]; then
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
            # 逐段校验 0-255。只用 ^([0-9]{1,3}\.){3}[0-9]{1,3}$ 是不够的:
            # 999.999.999.999 也能通过, 写进 network.lan.ipaddr 后 netifd
            # 无法绑定, 管理地址就失联了。这里每段限定 0-255。
            if echo "$CUSTOM_IP" | grep -Eq '^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$'; then
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

# 设置所有网口可访问网页终端
uci -q delete ttyd.@ttyd[0].interface

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''

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
# network 包在上面的分支里已单独提交, 这里不重复。
# 逐个包用 -q: 某个包不存在时(如未装 ttyd)只跳过它, 不刷错误也不中断脚本。
uci -q commit firewall
uci -q commit dropbear
uci -q commit ttyd

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by szwjp"
if [ -f "$FILE_PATH" ]; then
    sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"
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
