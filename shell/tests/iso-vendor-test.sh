#!/bin/sh
# ISO 安装器构建链路的断言
#
# 这条链路的性质: 固件 img.gz 要被包成一个可引导的 ISO 安装器。
# 原本这段逻辑放在第三方仓库里, CI 每次现 clone 一次再执行 ——
# 等于构建时运行了不受本仓库控制的代码, 上游一改产物就跟着变。
# 现在整条链路 vendored 进 iso/ 目录, 这里断言它不会再退回去。
#
# 用法: sh shell/tests/iso-vendor-test.sh
# 退出码 0 = 全部通过; 1 = 有失败
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
WORKFLOW="$REPO_ROOT/.github/workflows/build-x86-64.yml"
ISO_DIR="$REPO_ROOT/iso"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ✅ $1"; }
bad() { fail=$((fail + 1)); echo "  ❌ $1"; }

[ -f "$WORKFLOW" ] || { echo "❌ 找不到 $WORKFLOW" >&2; exit 1; }
[ -d "$ISO_DIR" ]   || { echo "❌ 找不到 $ISO_DIR" >&2; exit 1; }

# ================================================================
# 1. workflow 不再 clone 任何外部仓库
# ================================================================
# 这是本次改动的核心: clone 第三方仓库 = 构建时执行不受控代码。
# 断言整个 workflow 里没有任何 git clone。
if grep -qE '^\s*run:.*\bgit clone\b' "$WORKFLOW"; then
  bad "workflow 仍在 clone 外部仓库, 会执行不受本仓库控制的代码"
else
  ok "workflow 不再 clone 外部仓库"
fi

# ================================================================
# 2. ISO 构建走仓库内 vendored 的脚本
# ================================================================
if grep -q 'iso/autobuild.sh' "$WORKFLOW"; then
  ok "workflow 调用仓库内的 iso/autobuild.sh"
else
  bad "workflow 没有调用 iso/autobuild.sh"
fi

# 产物路径必须与上传步骤对得上
if grep -q 'iso/output/custom-installer-x86_64.iso' "$WORKFLOW"; then
  ok "workflow 上传的 ISO 路径与脚本产物一致"
else
  bad "workflow 上传的 ISO 路径与脚本产物不一致"
fi

# 发布说明也要用仓库内那份
if grep -q 'iso/info.md' "$WORKFLOW"; then
  ok "workflow 使用仓库内的 iso/info.md 作为发布说明"
else
  bad "workflow 没有使用仓库内的 iso/info.md"
fi

# ================================================================
# 3. vendored 文件齐全
# ================================================================
# 少任何一个, ISO 构建都会在容器里失败, 而且失败点很深(容器内部),
# 排查成本高。这里在 CI 早期用静态检查挡住。
for f in \
    iso/autobuild.sh \
    iso/info.md \
    iso/README.md \
    iso/LICENSE \
    iso/supportFiles/99-dhcp-en.network \
    iso/supportFiles/grub-standalone.cfg \
    iso/supportFiles/installChroot.sh \
    iso/supportFiles/override.conf \
    iso/supportFiles/sources.list \
    iso/supportFiles/custom/build.sh \
    iso/supportFiles/custom/ddd \
    iso/supportFiles/custom/grub.cfg \
    iso/supportFiles/custom/isolinux.cfg
do
    if [ -f "$REPO_ROOT/$f" ]; then
        ok "存在: $f"
    else
        bad "缺失: $f"
    fi
done

# MIT 许可证必须随 vendor 的代码一起保留
if grep -q 'MIT License' "$ISO_DIR/LICENSE" 2>/dev/null; then
    ok "iso/LICENSE 保留了上游 MIT 许可证"
else
    bad "iso/LICENSE 不是上游的 MIT 许可证"
fi

# 上游出处要记录在 README 里, 便于日后追溯与同步上游
if grep -q 'wukongdaily/img-installer' "$ISO_DIR/README.md" 2>/dev/null; then
    ok "iso/README.md 记录了上游出处"
else
    bad "iso/README.md 没有记录上游出处"
fi

# 文档与注释里不该残留外链。
# 这些链接不参与代码运行, 但会让仓库看起来依赖外部站点, 也不利于
# 离线阅读。出处信息用仓库名/commit 记录即可, 不需要带 URL。
# 注意排除 iso/LICENSE: 那是上游 MIT 许可证原文, 不可改动。
for f in "$ISO_DIR/README.md" "$ISO_DIR/info.md" "$ISO_DIR/autobuild.sh" \
         "$ISO_DIR/supportFiles/custom/build.sh"
do
    if grep -qE 'https?://[^ ]*github\.com' "$f"; then
        bad "文档/注释里残留 github 外链: ${f#$REPO_ROOT/}"
    else
        ok "无 github 外链: ${f#$REPO_ROOT/}"
    fi
done

# ================================================================
# 4. 基础镜像按 digest 钉死
# ================================================================
# 用 tag (debian:buster) 的话, 上游重新推送 tag 就会让产物跟着变。
# 必须钉 digest。
if grep -qE 'debian:buster@sha256:[0-9a-f]{64}' "$ISO_DIR/autobuild.sh"; then
    ok "debian 基础镜像按 digest 钉死"
else
    bad "debian 基础镜像没有按 digest 钉死, 产物不可复现"
fi

# 不该再有裸 tag。
# 只看真正生效的引用行(排除注释), 否则注释里提到 "debian:buster" 会被误判。
if grep -vE '^\s*#' "$ISO_DIR/autobuild.sh" | grep -qE 'debian:buster([^@[:alnum:]]|$)'; then
    bad "autobuild.sh 里还有未钉 digest 的 debian:buster 引用"
else
    ok "没有未钉 digest 的 debian:buster 引用"
fi

# ================================================================
# 5. Debian 包源的 HTTPS 加固
# ================================================================
# debian:buster 基础镜像不含 ca-certificates, 所以装证书前必须走 HTTP,
# 装完要切回 HTTPS。若这里退回明文, 容器内下载的工具包可能被中间人替换。
BS="$ISO_DIR/supportFiles/custom/build.sh"
if grep -q 'ca-certificates' "$BS"; then
    ok "容器内先安装 ca-certificates"
else
    bad "容器内没有安装 ca-certificates, 无法切 HTTPS"
fi

if grep -q 'https://archive.debian.org' "$BS"; then
    ok "容器内 apt 源已切到 HTTPS"
else
    bad "容器内 apt 源仍走明文 HTTP"
fi

# chroot 内的源也应为 HTTPS(证书已由 --include=ca-certificates 带进去)
if grep -q 'https://archive.debian.org' "$ISO_DIR/supportFiles/sources.list"; then
    ok "chroot 内 apt 源已切到 HTTPS"
else
    bad "chroot 内 apt 源仍走明文 HTTP"
fi

# ================================================================
# 6. 菜单文案与本仓库实际固件一致
# ================================================================
# 上游原样是 "Custom OpenWrt", 本仓库构建的是 ImmortalWrt。
if grep -q 'Custom OpenWrt' "$ISO_DIR/supportFiles/custom/ddd" \
   || grep -q 'Custom OpenWrt' "$ISO_DIR/supportFiles/custom/grub.cfg"; then
    bad "安装器菜单仍写着 Custom OpenWrt, 与本仓库固件不符"
else
    ok "安装器菜单文案与本仓库固件一致"
fi

# 发布说明里不能再有上游的加速站链接与徽章
if grep -qE 'cpolar|shields\.io' "$ISO_DIR/info.md"; then
    bad "iso/info.md 里还有第三方加速站链接或徽章"
else
    ok "iso/info.md 无第三方加速站链接"
fi

# 发布说明里的 LAN IP 必须与本仓库固件实际行为一致(99-custom.sh 用 192.168.1.1)
if grep -q '192\.168\.100\.1' "$ISO_DIR/info.md"; then
    bad "iso/info.md 里的 LAN IP 与本仓库固件实际值不符"
else
    ok "iso/info.md 的 LAN IP 与本仓库固件一致"
fi

# ================================================================
# 7. ISO 目录下的脚本必须语法正确
# ================================================================
# 这些脚本在容器里以 bash 执行, 语法错误只会在 ISO 构建时才暴露,
# 排查成本很高(要跑完整条 debootstrap 链路)。这里提前用 bash -n 挡住。
# 注意用 bash -n 而不是 sh -n: 容器里这些脚本是 bash 解释的,
# 且 ddd/build.sh 里有 bash 专有语法。
for f in \
    iso/autobuild.sh \
    iso/supportFiles/custom/build.sh \
    iso/supportFiles/installChroot.sh \
    iso/supportFiles/custom/ddd
do
    if bash -n "$REPO_ROOT/$f" 2>/dev/null; then
        ok "语法正确: $f"
    else
        bad "语法错误: $f"
        bash -n "$REPO_ROOT/$f" 2>&1 | head -3
    fi
done

echo
echo "iso-vendor-test: 通过 $pass, 失败 $fail"
[ "$fail" -eq 0 ] || exit 1
