#!/bin/sh
# 路由器管理地址(LAN 静态地址)校验 —— 全项目唯一实现。
#
# 用法:
#   1) 命令行: sh shell/validate-ip.sh 192.168.1.1   (通过 exit 0, 不通过 exit 1)
#   2) 函数:   . /usr/lib/imm/validate-ip.sh && ip_is_usable 192.168.1.1
#
# 校验目标不是"四段数字", 而是"能安全写进 network.lan.ipaddr 的 /24 主机地址":
#   - 每段 0-255, 不接受 01 这类前导零(避免解析器按八进制解释);
#   - 末段 1-254, 排除网络地址 .0 与广播地址 .255;
#   - 首段 1-223, 排除 0/8(本网络)、127/8(回环)、224-255(组播/保留);
#   - 排除 169.254/16(链路本地), 写进 lan.ipaddr 只会让管理面失联。
#
# 为什么单独成文件: workflow 的 bash 与固件首启脚本的 ash 必须用同一份规则。
# 各写一份迟早漂移 —— 以前的测试甚至把 0.0.0.0 和 255.255.255.255 断言成合法。
ip_is_usable() {
    # ash/dash/bash 都支持 local; 按纯 POSIX 检查会误报
    # shellcheck disable=SC3043
    local ip o1 o2 o4 rest

    ip=${1:-}
    printf '%s\n' "$ip" | grep -Eq '^((25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\.){3}(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$' || return 1

    o1=${ip%%.*}
    rest=${ip#*.}
    o2=${rest%%.*}
    rest=${rest#*.}
    o4=${rest#*.}

    # /24 内的可用主机地址: .0 是网络地址, .255 是广播地址
    [ "$o4" -ge 1 ] && [ "$o4" -le 254 ] || return 1
    # 首段: 0 本网络、127 回环、224-255 组播/保留
    [ "$o1" -ge 1 ] && [ "$o1" -le 223 ] || return 1
    [ "$o1" -eq 127 ] && return 1
    # 169.254/16 链路本地(APIPA)
    if [ "$o1" -eq 169 ] && [ "$o2" -eq 254 ]; then
        return 1
    fi

    return 0
}

# 被 . (source) 时 $0 是调用方脚本, 不进入命令行分支
if [ "${0##*/}" = "validate-ip.sh" ]; then
    if ip_is_usable "${1:-}"; then
        exit 0
    fi
    printf '非法路由器管理地址: %s\n' "${1:-<空>}" >&2
    exit 1
fi
