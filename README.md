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
│   └── test.yml                    # push/PR 触发: 语法检查 + 全部自测 (不联网)
├── x86-64/                      # x86-64 平台配置目录
│   ├── build.sh                 # 统一构建脚本 (25.12.x, APK)
│   └── imm.config               # 25.12.x 版本配置
├── shell/                       # 构建脚本和包管理目录
│   ├── custom-packages.sh       # 核心软件包配置 + 官方 LuCI 应用清单 (25.12.x, APK)
│   ├── validate-ip.sh           # 管理地址校验唯一实现 (workflow 与固件首启脚本共用)
│   ├── refresh-release-date.sh  # 刷新 release 的 published_at, 兼 draft 兜底发布
│   └── tests/                   # 构建脚本自测 (全部不联网, CI 里跑)
│       ├── run-all.sh                    # 统一入口, 自动跑目录下全部 *-test.sh
│       ├── custom-packages-test.sh       # 核心集/排除项/静态表 静态断言
│       ├── refresh-release-date-test.sh  # refresh-release-date.sh 行为自测
│       ├── firmware-config-test.sh       # 首启脚本/构建脚本 行为断言
│       ├── iso-vendor-test.sh            # ISO 链路: vendored/文案/写盘护栏
│       ├── validate-ip-test.sh           # 管理地址校验: 主机地址语义矩阵
│       └── workflow-ci-test.sh           # 构建稳定性: 并发/超时/digest/凭据/输入注入
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

- **单网口设备**：默认采用 DHCP 模式，自动获取 IP
- **多网口设备**：默认 WAN 口采用 DHCP 模式，LAN 口 IP 为 192.168.1.1（最后一个网口为 WAN，其余为 LAN）
- 若在工作流中勾选了拨号信息，则 WAN 口模式为 PPPoE 拨号模式（仅多网口设备生效）
- 建议拨号用户使用之前重启一次光猫

### 包集合怎么组织

- **`shell/custom-packages.sh`** 只放封装层的**核心组件**（系统基础件、网络核心、驱动、存储、引导、中文界面底线）。
- **要排除的包**写在同一文件的 `EXCLUDE_PACKAGES`，用 ImageBuilder 的 `-包名` 语法（表示这个包不装进固件）。当前排除了 `autocore`（自动调频）——x86 的 ImageBuilder 默认会带上它，与核心集口径不一致。
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
- **管理面默认收敛**：SSH 只监听 LAN；ttyd（网页终端）默认关闭，需要时在 LuCI【系统 - 终端】手动开启。固件默认 root 无密码，root 无密码时首启会在登录 banner 上提示设置密码；设置密码前，不要把设备接入不可信网络。
- **单网口 DHCP 模式**下设备会成为上游局域网的一员，管理面也就在那一侧。该模式只为首次访问方便，长期使用请设置 root 密码，或改用多网口/静态地址。
- **管理地址只接受 /24 内的可用主机地址**：拒绝 0.0.0.0、网络地址（.0）、广播地址（.255）、回环、组播/保留段和 169.254/16。规则只有一份 `shell/validate-ip.sh`，workflow 与固件首启脚本共用，不再两处维护正则。
- **启用 PPPoE 时，宽带密码会以明文写入固件镜像**（首启脚本读完即删设备上的副本，但镜像本身仍含明文）。这类固件请勿公开分发。CI 日志里不再回显凭据，但这只解决日志，不解决镜像。
- 发布资产除固件外还带 `<固件>.sha256`（下载后 `sha256sum -c` 校验）与 `.manifest`（固件内软件包清单）。

### 构建稳定性约定

- 两个 release 的 tag 固定（`Autobuild-x86-64`、`Custom-Installer-x86_64-ISO`），工作流用 `concurrency` 串行化，避免并发 dispatch 互相覆盖同名资产。
- ImageBuilder 镜像按 digest 钉死（见工作流里的版本 → digest 映射，新增版本要补一行）；ISO 链路的 `debian:buster` 同样按 digest 钉死。
- 工作流输入只经 `env:` 传入脚本，`run:` 里不内联 `${{ inputs.* }}`；管理地址校验统一走 `shell/validate-ip.sh`。
- release 日期刷新是 draft→published 往返，失败路径由 `--ensure-published` 兜底，避免 release 卡在 draft 对外消失。
- push / pull_request 会跑 `test.yml`（语法检查 + 全部自测，不联网），规则被改坏会在提交时就红，而不是等到下次手动出图。
