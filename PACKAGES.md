# 支持的第三方软件列表

> 第三方软件 = ImmortalWrt 官方源以外的软件包，来源为 [wukongdaily/apk](https://github.com/wukongdaily/apk) 仓库的 `run/x86` 目录（apk 格式）。
> 构建时由 `x86-64/build.sh` 拉取该仓库，`shell/prepare-packages.sh` 解包整理进 ImageBuilder 的 `packages/` 目录。
>
> 「当前编译」列：
> - ✅：已写入 `shell/custom-packages.sh`，默认编译进固件
> - ❌：源里有，但当前未启用；需要时把包名加进 `shell/custom-packages.sh` 对应行即可
>
> 依赖说明：`sing-box` / `xray-core` / `hysteria` / `naiveproxy` / `kmod-nft-socket` / `kmod-nft-tproxy` 等**代理内核包在 ImmortalWrt 官方源里**，不在本表范围内，由官方源直接提供。
>
> 官方 LuCI 应用不在这张表里：它们写在 `shell/custom-packages.sh` 末尾的 `LUCI_APPS`（应用名，不是包名），构建时按本次构建版本从官方源索引解析成真实包名。

| 第三方软件名称                | 简介 / 功能描述                          | 当前编译 | 来源 / 项目地址                                                                                 |
| ------------------------ | --------------------------------- | ---- | ------------------------------------------------------------------------------------ |
| luci-app-store           | iStore 应用商店                          | ❌   | [linkease/luci-app-store](https://github.com/linkease/istore)                                |
| luci-app-quickstart      | iStore 首页和网络向导                        | ❌   | [kiddin9/kwrt-packages](https://github.com/kiddin9/kwrt-packages/tree/main/luci-app-quickstart) |
| luci-app-run             | 一键运行脚本                              | ❌   | [wukongdaily/apk](https://github.com/wukongdaily/apk/tree/master/run/x86)                                      |
| luci-theme-aurora        | 极光主题                                 | ❌   | [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora)                      |
| luci-app-aurora-config   | 极光主题配置                              | ❌   | [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora)                      |
| luci-app-mosdns          | 高性能 DNS 分流器，支持 DoH / DoQ 等             | ❌   | [sbwml/luci-app-mosdns](https://github.com/sbwml/luci-app-mosdns)                              |
| luci-app-passwall        | 代理工具                                | ❌   | [Openwrt-Passwall/openwrt-passwall](https://github.com/Openwrt-Passwall/openwrt-passwall)      |
| luci-app-passwall2       | 代理工具                                | ✅   | [Openwrt-Passwall/openwrt-passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2)    |
| luci-app-quickfile       | 文件管理器                                | ❌   | [sbwml/luci-app-quickfile](https://github.com/sbwml/luci-app-quickfile)                        |
| luci-app-partexp         | 分区扩容插件                              | ❌   | [sirpdboy/luci-app-partexp](https://github.com/sirpdboy/luci-app-partexp)                      |
| luci-app-bandix          | 流量监控                                | ✅   | [timsaya/luci-app-bandix](https://github.com/timsaya/luci-app-bandix)                        |
| luci-app-clashoo         | Clash 图形化客户端                         | ❌   | [wukongdaily/apk](https://github.com/wukongdaily/apk/tree/master/run/x86)                                      |
| luci-app-daed            | 代理工具                                | ❌   | [daeuniverse/dae](https://github.com/daeuniverse/dae)                                         |
| luci-app-daede           | 代理工具                                | ❌   | [daeuniverse/dae](https://github.com/daeuniverse/dae)                                         |
| luci-app-nikki           | 代理工具                                | ❌   | [nikkinikki-org/nikki](https://github.com/nikkinikki-org/nikki)                                |
| luci-app-lucky           | Lucky 大吉：软硬路由公网神器，ipv6/ipv4 端口转发、反向代理 | ❌   | [gdy666/lucky](https://github.com/gdy666/lucky)                                                |
| luci-app-rtp2httpd       | IPTV 流媒体转发服务器                        | ❌   | [stackia/rtp2httpd](https://github.com/stackia/rtp2httpd)                                     |
| luci-app-ssr-plus        | 代理工具                                | ❌   | [coolsnowwolf/luci-app-ssr-plus](https://github.com/fw876/helloworld)                         |
| luci-app-taskplan        | 任务计划                                | ❌   | [wukongdaily/apk](https://github.com/wukongdaily/apk/tree/master/run/x86)                                      |

## 内核自动下载

`x86-64/build.sh` 会在启用对应插件时自动拉取代理内核，不需要手动准备：

- 启用 `luci-app-openclash` → 拉取 OpenClash 官方 apk、clash_meta、GeoIP.dat / GeoSite.dat
- 启用 `luci-app-ssr-plus` → 拉取 mihomo 内核二进制（`files/usr/bin/mihomo`）
