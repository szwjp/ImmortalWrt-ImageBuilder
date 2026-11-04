# ISO 安装器构建

本目录把固件 `.img.gz` 打包成可引导的安装器 ISO：Debian live 环境 + 引导菜单 +
`ddd` 安装脚本，引导后输入 `ddd` 即可把固件写进目标磁盘。

## 出处

代码最初来自第三方仓库 `wukongdaily/img-installer`（fork 自 `dpowers86/debian-live`），
MIT 协议，作者 Daniel William Powers。原始许可证保留在 [`iso/LICENSE`](./LICENSE)。

搬进来的原因：原先 CI 每次构建都现 `git clone` 那个仓库再执行，等于在构建时
运行了不受本仓库控制的代码，上游一改代码产物就跟着变，且无法复现。现在整条
链路在本仓库内，不再有任何 clone。

**上游基准 commit**：`361ea6138094a2417e62edd01f73fa1160e93e01`（2026-05-16）

## 与上游的差异

| 文件 | 改动 |
|------|------|
| `autobuild.sh` | 重写。原版要 `cd` 进 clone 出来的目录、靠相对路径找 `supportFiles`；现在自包含，脚本所在目录即工作目录。Debian 基础镜像由 `debian:buster` 改为 `debian:buster@sha256:58ce6f12...` 按 digest 钉死，tag 指向的内容会随上游重新推送而变化。固件以只读方式挂进容器。 |
| `supportFiles/custom/build.sh` | Debian 包源先走 HTTP 装 `ca-certificates`（`debian:buster` 基础镜像只有 91 个核心包，不含证书），装完立刻切 HTTPS，后续工具安装走加密通道。debootstrap 保持 HTTP——它的二阶段会在还没证书的 chroot 里跑 apt，走 HTTPS 会中断；而 buster 的 Release 带 GPG 签名，debootstrap 默认校验，完整性有保障。 |
| `supportFiles/sources.list` | 由明文改为加密通道。chroot 在 debootstrap 阶段已通过 `--include=ca-certificates` 拿到证书，所以这里能用 HTTPS。 |
| `supportFiles/custom/ddd` | 菜单文案由「Custom OpenWrt」改为「ImmortalWrt」，与本仓库实际构建的固件一致。 |
| `supportFiles/custom/grub.cfg` | 引导菜单项名称同上。 |
| `info.md` | 重写发布说明。删掉上游的 cpolar 加速站链接与 shields.io 徽章；修正上游说明里「LAN 口 IP 为 192.168.100.1」的错误（本仓库固件实际是 `192.168.1.1`，且可在工作流里改）。 |

其余文件（`installChroot.sh`、`override.conf`、`99-dhcp-en.network`、
`grub-standalone.cfg`、`isolinux.cfg`）与上游一致。

上游仓库里其余内容没有搬过来：`esirplayground` / `ezopwrt` / `haos` /
`istoreos` / `immortalwrt` 等其它固件变体、上游自己的 GitHub Actions 工作流、
以及与 ISO 构建无关的脚本。本仓库只构建 ImmortalWrt x86-64，用不到它们。

## 用法

```sh
bash iso/autobuild.sh <固件.img.gz>
```

产物：`iso/output/custom-installer-x86_64.iso`

## 外部依赖

构建过程仍会联网，只剩三处，且都指向官方源：

- `docker.io` —— `debian:buster` 基础镜像（按 digest 钉死），用于跑
  debootstrap 和 xorriso
- `archive.debian.org` —— Debian buster 归档包（Buster 已 EOL，只有归档源）
- `deb.debian.org` —— 不再使用

## 更新到新的上游版本

上游仓库名见「出处」一节。拉取到本地后切到目标 commit，再对比
`supportFiles/custom/` 与本目录 `iso/supportFiles/custom/` 的差异，把上游的修复
择要带过来，同时保留上表里记录的本地改动。
