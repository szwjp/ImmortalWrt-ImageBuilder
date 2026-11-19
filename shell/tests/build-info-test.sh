#!/bin/sh
# build-info.sh 的行为测试: 字段是否齐全、哈希是否算对、缺参数是否拒绝
#
# 用法: sh shell/tests/build-info-test.sh
# 退出码 0 = 全部通过; 1 = 有失败
set -u

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/../.." && pwd)
BUILD_INFO="$REPO_ROOT/shell/build-info.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ✅ $1"; }
bad() { fail=$((fail + 1)); echo "  ❌ $1"; }

[ -f "$BUILD_INFO" ] || { echo "❌ 找不到 $BUILD_INFO" >&2; exit 1; }

if ! command -v jq >/dev/null 2>&1; then
  echo "  ⏭️  环境无 jq, 跳过 build-info 测试"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/dist"

printf 'fake firmware image' > "$TMP/dist/test-squashfs-combined-efi.img.gz"
printf 'manifest line' > "$TMP/dist/test.manifest"

run_ok() {
  COMMIT_SHA=abc1234567890 \
  LUCI_VERSION=25.12.2 \
  IMAGEBUILDER_DIGEST='immortalwrt/imagebuilder@sha256:deadbeef' \
  REPOSITORY=szwjp/ImmortalWrt-ImageBuilder \
  RUN_ID=42 \
  RUN_ATTEMPT=1 \
  WORKFLOW_NAME='Build ImmortalWrt x86-64' \
  REF_NAME=master \
  sh "$BUILD_INFO" "$@"
}

# ---- 文件形态产物: 固件 + manifest ----
if run_ok "$TMP/dist/build-info.json" "$TMP/dist/test-squashfs-combined-efi.img.gz" >/dev/null 2>&1; then
  ok "生成 build-info.json"
else
  bad "生成 build-info.json 失败"
fi

JSON="$TMP/dist/build-info.json"
check_jq() {
  if jq -e "$1" "$JSON" >/dev/null 2>&1; then
    ok "$2"
  else
    bad "$2"
  fi
}

check_jq '.schema_version == 1' "schema_version=1"
check_jq '.commit == "abc1234567890"' "记录 commit"
check_jq '.immortalwrt_version == "25.12.2"' "记录版本"
check_jq '.imagebuilder_digest | test("imagebuilder@sha256:")' "记录 ImageBuilder digest"
check_jq '.artifact.path == "test-squashfs-combined-efi.img.gz"' "记录产物文件名"
check_jq '.artifact.sha256 | test("^[0-9a-f]{64}$")' "产物 sha256 格式正确"
ARTIFACT_SIZE=$(wc -c < "$TMP/dist/test-squashfs-combined-efi.img.gz" | tr -d '[:space:]')
check_jq ".artifact.size_bytes == $ARTIFACT_SIZE" "产物大小正确"
check_jq '.manifest.path == "test.manifest"' "记录 manifest"
check_jq '.manifest.sha256 | test("^[0-9a-f]{64}$")' "manifest sha256 格式正确"
check_jq '.inputs.config.path == "imm.config"' "记录 imm.config"
check_jq '.inputs.packages.path == "custom-packages.sh"' "记录包清单文件"
check_jq '.extra_artifact == null' "无附加产物时为 null"
check_jq '.iso_builder == null' "img 产物不写 ISO builder"

# ---- ISO 形态产物: 附加 firmware 与 debian 基础镜像 ----
printf 'fake iso' > "$TMP/dist/custom-installer-x86_64.iso"
printf 'extra firmware' > "$TMP/extra.img.gz"
if run_ok "$TMP/dist/build-info-iso.json" "$TMP/dist/custom-installer-x86_64.iso" "$TMP/extra.img.gz" >/dev/null 2>&1; then
  ok "生成 ISO build-info.json"
else
  bad "生成 ISO build-info.json 失败"
fi
ISO_JSON="$TMP/dist/build-info-iso.json"
if jq -e '.extra_artifact.path == "extra.img.gz"' "$ISO_JSON" >/dev/null 2>&1; then
  ok "ISO 记录附加固件"
else
  bad "ISO 没有记录附加固件"
fi
if jq -e '.iso_builder.base_image | test("debian:buster@sha256:[0-9a-f]{64}")' "$ISO_JSON" >/dev/null 2>&1; then
  ok "ISO 记录 buster 基础镜像(按 digest)"
else
  bad "ISO 没有记录基础镜像"
fi

# ---- 失败路径 ----
if COMMIT_SHA= LUCI_VERSION=25.12.2 IMAGEBUILDER_DIGEST=x sh "$BUILD_INFO" "$TMP/a.json" "$TMP/dist/test-squashfs-combined-efi.img.gz" >/dev/null 2>&1; then
  bad "缺少 COMMIT_SHA 时没有拒绝"
else
  ok "缺少环境变量时拒绝生成"
fi
if run_ok "$TMP/b.json" "$TMP/dist/not-exist.img.gz" >/dev/null 2>&1; then
  bad "产物不存在时没有拒绝"
else
  ok "产物不存在时拒绝生成"
fi

echo
echo "build-info-test: 通过 $pass, 失败 $fail"
[ "$fail" -eq 0 ] || exit 1
