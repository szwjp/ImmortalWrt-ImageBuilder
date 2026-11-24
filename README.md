# ImmortalWrt-ImageBuilder

基于 CI 的 ImageBuilder 工作流，用于自动化构建 ImmortalWrt 固件（仅支持 x86-64）。

## 功能特性

- 支持自定义固件大小（默认 1GB）
- 支持可选预安装 Docker
- 官方 LuCI 应用按需启用（包名直接写在配置里）
- 支持 25.12.x 版本
- 提供 ISO 安装器格式

## 📁 项目功能目录树

```
ImmortalWrt-ImageBuilder/
├── .github/workflows/          # GitHub Actions 工作流目录
│   ├── build-x86-64.yml            # 统一构建工作流 (通过参数选择版本和输出格式)
│   ├── clean-workflow.yml          # 工作流清理
│   └── test.yml                    # push/PR 触发: 语法检查 + ShellCheck/actionlint + 全部自测
├── .github/dependabot.yml       # github-actions 版本更新 PR (配合 SHA 固定)
├── x86-64/                      # x86-64 平台配置目录
│   ├── build.sh                 # 统一构建脚本 (25.12.x, APK)
│   └── imm.config               # 25.12.x 版本配置
├── shell/                       # 构建脚本和包管理目录
│   ├── custom-packages.sh       # 核心软件包配置 + 官方 LuCI 应用清单 (25.12.x, APK)
│   ├── validate-ip.sh           # 管理地址校验唯一实现 (workflow 与固件首启脚本共用)
│   ├── build-info.sh            # 生成 build-info.json: 构建输入与产物指纹
│   ├── refresh-release-date.sh  # 刷新 release 的 published_at, 兼 draft 兜底发布
│   └── tests/                   # 构建脚本自测 (全部不联网, CI 里跑)
│       ├── run-all.sh                    # 统一入口, 自动跑目录下全部 *-test.sh
│       ├── custom-packages-test.sh       # 核心集/排除项/静态表 静态断言
│       ├── refresh-release-date-test.sh  # refresh-release-date.sh 行为自测
│       ├── firmware-config-test.sh       # 首启脚本/构建脚本 行为断言
│       ├── iso-vendor-test.sh            # ISO 链路: vendored/文案/写盘护栏
│       ├── validate-ip-test.sh           # 管理地址校验: 主机地址语义矩阵
│       ├── build-info-test.sh            # build-info.json 字段/哈希/失败路径
│       └── workflow-ci-test.sh           # 构建稳定性: 并发/超时/digest/凭据/输入注入/SHA 固定
├── files/etc/uci-defaults/      # 固件自定义文件目录
│   └── 99-custom.sh             # 固件首次启动配置脚本
└── iso/                         # ISO 安装器构建 (vendored, 不再 clone 第三方仓库)
    ├── autobuild.sh             # 固件 img.gz -> 安装器 ISO
    ├── info.md                  # ISO 发布说明
    ├── supportFiles/            # Debian live 环境与引导配置
    └── README.md                # 上游出处与本地改动说明
```

## 操作手册

### 基本用法

1. Fork 本项目
2. 在 fork 后的项目中点击 【Actions】
3. 找到需要的工作流后点击 【Run workflow】

### 固件默认属性

- **单网口设备**：默认采用 DHCP 模式，自动获取 IP；首启会生成随机 root 密码并输出到本机控制台（见下方「特别说明」）
- **多网口设备**：默认 WAN 口采用 DHCP 模式，LAN 口 IP 为 192.168.1.1（最后一个网口为 WAN，其余为 LAN）；自动映射支持 **最多 9 个物理网口**，超过则不做自动映射（见「特别说明」）
- **IPv6（wan6）**：只有在镜像里还没有 `wan6`、且 WAN 不是 PPPoE 时，脚本才会补一个指向物理 WAN 口的 DHCPv6 客户端；已有 `wan6` 一律不覆盖。**启用 PPPoE 时不创建也不修改 `wan6`**：PPP 链路起来后 `/lib/netifd/ppp6-up` 会自动 `ubus call network add_dynamic` 建一个名为 `wan_6` 的动态 DHCPv6 客户端（它不在 UCI 配置里，`uci show network` 看不到），IPv6 由它负责；再写一个 UCI `wan6` 只会让 LuCI 里出现两个 IPv6 条目。需要自己指定 IPv6 时，请在 LuCI 里手工添加。升级保留配置的机器若已存在 UCI `wan6`，首启日志会提示与 `wan_6` 重复（日志只提示、不自动删）。另外，平台的 `wan_6` 只在 `wan.ipv6` 未设置/`auto` 时才会被 `ppp6-up` 创建；脚本在 PPPoE 分支会删掉 `wan.ipv6`，避免上游把它写成 `1` 之后整机没有任何 IPv6 客户端。
- 若在工作流中勾选了拨号信息，则 WAN 口模式为 PPPoE 拨号模式（仅多网口设备生效）
- 建议拨号用户使用之前重启一次光猫

### 包集合怎么组织

- **`shell/custom-packages.sh`** 只放封装层的**核心组件**（系统基础件、网络核心、驱动、存储、引导、中文界面底线）。
- **要排除的包**写在同一文件的 `EXCLUDE_PACKAGES`，用 ImageBuilder 的 `-包名` 语法（表示这个包不装进固件）；变量必须保留定义（`build.sh` 是 `set -u`，缺失会直接退出）。
- **当前排除 `autocore`**：x86 的 ImageBuilder 默认带它。它的 `/etc/init.d/autocore` 每次开机都会对所有 `eth*` 强制 `ethtool -K` 打开 offload、写入 RPS flow 表、并把 igc（I225/I226）环形缓冲拉到最大，会盖掉固件里显式配置的网卡参数。本固件的原则是网卡参数只由显式配置决定，因此整包排除；代价是 LuCI 状态页的「架构」行退回内核默认显示（少了物理核数/频率）。它**不是**调频包——调频是另一个 arm-only 的 `cpufreq`。
- **官方 LuCI 应用**写在 `custom-packages.sh` 末尾的「ImmortalWrt 官方 LuCI 应用」区段，直接写包名（`luci-i18n-<名>-zh-cn`），按需启用/注释：

  ```sh
  CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-homeproxy-zh-cn"
  #CUSTOM_PACKAGES="$CUSTOM_PACKAGES luci-i18n-nextdns-zh-cn"
  ```

  包名写错时 apk 装包会直接失败，构建不会静默出图。`luci-i18n-<名>-zh-cn` 的依赖闭包会自动带上对应的 `luci-app-<名>` 本体。

- **Docker 插件**由工作流的 `include_docker` 输入项控制（`build.sh` 按需追加 `luci-i18n-dockerman-zh-cn`），不写在静态表里——否则该输入项就失效了。

- **非官方 LuCI 插件**不在官方源里，当前**全部清除**，以后统一安排。需要时再按统一方案接回（届时会带上自己的包源与固件内配置）。

### 特别说明

- **单网口设备**（DHCP 模式）的唯一网口属于 LAN zone（默认入站放行），WebUI 直接可访问；脚本不会去改 WAN zone，因此以后自行添加 WAN 接口也不会意外带出一个放行。**多网口设备**用 LAN 静态地址访问，WAN 保持默认拒绝。
- **管理面默认收敛**：SSH 只监听 LAN；ttyd（网页终端）默认关闭，需要时在 LuCI【系统 - 终端】手动开启。
- **单网口 DHCP 模式的 root 密码**：设备会成为上游局域网的一员，同网段任何主机都能直连 22/443，所以首启脚本在 root 还没有密码时生成 16 位随机密码（字符集排除 0/O/1/l/I/o 等易混字符），并：
  1. 打印到**本机控制台**（/dev/console，接显示器或串口即可看到；写不进去时退回 /dev/tty1）；
  2. 落一份 /root/.first-boot-password（权限 600，仅 root 可读）；
  3. 在 /etc/banner 写清「密码在哪」，**不写密码本身**（banner 在 SSH 登录前就会显示）。

  登录后请在 LuCI【系统 - 管理权】修改密码，并删除该文件（命令行：`rm /root/.first-boot-password`）。

  **控制台是唯一一次取密码的机会**：完全无显示器、无串口的单网口机器，不要直接把它 DHCP 接入不可信网络，先接显示器完成首启、改好密码再用。多网口设备不生成随机密码（LAN 是独立网段），保持开箱即用；root 无密码时首启仍会在 banner 上提示。
- 随机密码只在 **root 当前没有密码** 时生成；脚本被手动重跑不会改掉你已设置的密码。
- **多网口默认开启 STP**（`br-lan` 的 `stp=1`）：多个 LAN 口接同一交换机时防环。代价是上电后端口要经过 802.1D 的 listening/learning 才转发，LAN 可能延迟数十秒才通（具体秒数未实测）。
- **重跑首启脚本是安全的**：随机密码、banner 提示、br-lan 端口、打包者后缀都做了幂等；uhttpd 端口、ttyd 开关、docker 防火墙只在「还不是目标状态」时才改。例外是把 uhttpd 改到 8080/8443 以外的端口，重跑会被接管回 8080/8443。
- **结构性失败会保留脚本重试**：找不到 `br-lan` 设备段、或 `network` 写盘失败时，脚本以非 0 退出，`/etc/uci-defaults` 不会删它，下次启动重试；环境差异（没装 ttyd/nginx 等）仍返回 0，避免反复重跑冲掉你在 LuCI 里的改动。
- **网口自动映射上限 9 个**：脚本按 `/sys/class/net/*` 的 glob 顺序枚举物理口，那是字典序。名字里一旦出现两位数（`eth10`），它会排在 `eth2` 前面，「最后一个口当 WAN」就配错，而且不报错。实测 **10 口（eth0..eth9）排序仍然正确，错位从第 11 口开始**；脚本仍把上限取 9，多留一档余量。**检测到 10 个及以上物理口时，脚本不写任何 network 配置**，保留镜像默认网络（通常 `lan` 是 br-lan 含 eth0，`wan` 取决于存在哪些网口），其余网口请在 LuCI【网络 - 接口】手工指定。首启日志 `/tmp/99-custom.log` 里会记录每个口的名称、MAC、驱动和 PCI 路径，便于对照实物面板核对。
- **管理地址只接受 /24 内的可用主机地址**：拒绝 0.0.0.0、网络地址（.0）、广播地址（.255）、回环、组播/保留段和 169.254/16。规则只有一份 `shell/validate-ip.sh`，workflow 与固件首启脚本共用，不再两处维护正则。
- **启用 PPPoE 时，宽带密码会以明文写入固件镜像**（首启脚本读完即删设备上的副本，但镜像本身仍含明文）。这类固件请勿公开分发。CI 日志里不再回显凭据，但这只解决日志，不解决镜像。
- 发布资产除固件外还带 `<固件>.sha256`（下载后 `sha256sum -c` 校验）、`.manifest`（固件内软件包清单）和 `build-info.json`（commit、版本、ImageBuilder digest、输入文件与产物 SHA256）。
- **ISO 安装器是顺带产出，保持现状**：构建宿主与安装器用户态仍是 Debian Buster（已 EOL），安装器内核较旧，未做新硬件和安全更新验证。它只适合在已知可启动的 x86-64 机器上写固件，不作为长期维护的发行版；迁移到受支持的 Debian 需要重做 debootstrap、live-boot 和 BIOS/UEFI 引导验证，暂不排期。

### 构建稳定性约定

- 两个 release 的 tag 固定（`Autobuild-x86-64`、`Custom-Installer-x86_64-ISO`），工作流用 `concurrency` 串行化，避免并发 dispatch 互相覆盖同名资产。
- ImageBuilder 镜像按 digest 钉死（见工作流里的版本 → digest 映射，新增版本要补一行）；ISO 链路的 `debian:buster` 同样按 digest 钉死。
- 工作流输入只经 `env:` 传入脚本，`run:` 里不内联 `${{ inputs.* }}`；管理地址校验统一走 `shell/validate-ip.sh`。
- 第三方 Actions 固定到完整 commit SHA（行尾注释保留版本号），版本更新走 Dependabot PR，不自动漂移。
- CI 除语法检查外还跑 ShellCheck（warning 及以上）与 actionlint（1.7.12，下载后先校验 SHA256）。
- 每次构建生成 `build-info.json` 并随 release 上传，可追溯 commit、ImageBuilder digest、配置文件/包清单/产物哈希。
- release 日期刷新是 draft→published 往返，失败路径由 `--ensure-published` 兜底，避免 release 卡在 draft 对外消失。
- push / pull_request 会跑 `test.yml`（语法检查 + 全部自测，不联网），规则被改坏会在提交时就红，而不是等到下次手动出图。
