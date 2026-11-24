#!/bin/sh
# 首启时关掉 autocore 的开机调优脚本, 只保留它的 /sbin/cpuinfo(状态页用)。
#
# 为什么关: /etc/init.d/autocore 会在每次开机对所有 eth* 强制 ethtool -K 打开
# rx/tx-checksum / sg / gso / tso / ufo, 把 RPS flow 表设成 4096×线程, 并对
# igc(I225/I226) 把环形缓冲拉到最大。这些是隐式改写, 会盖掉固件里显式配置的
# 网卡参数, 也盖掉用户在 LuCI/命令行里的手工调整。
#
# 为什么用 disable 而不是 chmod -x: disable 只删 /etc/rc.d/S99autocore 这个
# 启动链接, 脚本本体还在, 反悔时 /etc/init.d/autocore enable 就能恢复;
# chmod -x 之后 enable 会重新建链接但脚本仍不可执行, 更难排查。
#
# 退出码必须为 0: uci-defaults 只在退出 0 时删除自身脚本, 非 0 会每次开机重试。
if [ -x /etc/init.d/autocore ]; then
	/etc/init.d/autocore disable
fi

exit 0
