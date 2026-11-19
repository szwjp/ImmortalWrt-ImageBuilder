#!/bin/sh
# 生成 build-info.json: 一次构建的输入与产物指纹, 随 release 一起发布。
#
# 用法: sh shell/build-info.sh <输出 json> <产物文件> [附加产物文件]
#
# 环境变量(workflow 传入):
#   COMMIT_SHA          必填, 构建对应的 commit
#   LUCI_VERSION        必填, ImmortalWrt 版本
#   IMAGEBUILDER_DIGEST 必填, 形如 immortalwrt/imagebuilder@sha256:...
#   REPOSITORY / REF_NAME / RUN_ID / RUN_ATTEMPT / WORKFLOW_NAME 选填
#
# 只依赖 jq、sha256sum(或 macOS 的 shasum) 和 wc, 不联网。
set -eu

usage() {
    echo "用法: $0 <输出 json> <产物文件> [附加产物]" >&2
    exit 1
}

OUT=${1:-}
ARTIFACT=${2:-}
EXTRA=${3:-}

[ -n "$OUT" ] && [ -n "$ARTIFACT" ] || usage
[ -f "$ARTIFACT" ] || { echo "错误: 产物不存在: $ARTIFACT" >&2; exit 1; }
if [ -n "$EXTRA" ] && [ ! -f "$EXTRA" ]; then
    echo "错误: 附加产物不存在: $EXTRA" >&2
    exit 1
fi

missing=""
[ -n "${COMMIT_SHA:-}" ] || missing="$missing COMMIT_SHA"
[ -n "${LUCI_VERSION:-}" ] || missing="$missing LUCI_VERSION"
[ -n "${IMAGEBUILDER_DIGEST:-}" ] || missing="$missing IMAGEBUILDER_DIGEST"
if [ -n "$missing" ]; then
    echo "错误: 缺少环境变量:$missing" >&2
    exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "错误: 需要 jq" >&2; exit 1; }

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        echo "错误: 找不到 sha256sum 或 shasum" >&2
        exit 1
    fi
}

file_obj() {
    jq -n \
        --arg path "$(basename -- "$1")" \
        --arg sha256 "$(sha256_of "$1")" \
        --argjson size_bytes "$(wc -c < "$1" | tr -d '[:space:]')" \
        '{path:$path, sha256:$sha256, size_bytes:$size_bytes}'
}

# ImageBuilder 的 .manifest 与固件同目录; ISO 没有 manifest
manifest_json=null
case "$ARTIFACT" in
    *.img.gz)
        manifest=$(ls "$(dirname -- "$ARTIFACT")"/*.manifest 2>/dev/null | head -1 || true)
        if [ -n "$manifest" ]; then
            manifest_json=$(file_obj "$manifest")
        fi
        ;;
esac

extra_json=null
if [ -n "$EXTRA" ]; then
    extra_json=$(file_obj "$EXTRA")
fi

# ISO 构建的宿主镜像(当前固定 debian:buster), 记录在案便于追溯
iso_json=null
case "$ARTIFACT" in
    *.iso)
        iso_image=$(grep -oE 'debian:buster@sha256:[0-9a-f]{64}' "$REPO_ROOT/iso/autobuild.sh" | head -1 || true)
        if [ -n "$iso_image" ]; then
            iso_json=$(jq -n --arg image "$iso_image" '{base_image:$image}')
        fi
        ;;
esac

mkdir -p "$(dirname -- "$OUT")"
jq -n \
    --arg repository "${REPOSITORY:-unknown}" \
    --arg commit "$COMMIT_SHA" \
    --arg ref "${REF_NAME:-}" \
    --arg workflow "${WORKFLOW_NAME:-}" \
    --arg run_id "${RUN_ID:-}" \
    --arg run_attempt "${RUN_ATTEMPT:-}" \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg version "$LUCI_VERSION" \
    --arg digest "$IMAGEBUILDER_DIGEST" \
    --argjson config "$(file_obj "$REPO_ROOT/x86-64/imm.config")" \
    --argjson packages "$(file_obj "$REPO_ROOT/shell/custom-packages.sh")" \
    --argjson artifact "$(file_obj "$ARTIFACT")" \
    --argjson extra_artifact "$extra_json" \
    --argjson manifest "$manifest_json" \
    --argjson iso_builder "$iso_json" \
    '{
        schema_version: 1,
        repository: $repository,
        commit: $commit,
        ref: $ref,
        workflow: $workflow,
        run_id: $run_id,
        run_attempt: $run_attempt,
        generated_at: $generated_at,
        immortalwrt_version: $version,
        imagebuilder_digest: $digest,
        inputs: {config: $config, packages: $packages},
        artifact: $artifact,
        extra_artifact: $extra_artifact,
        manifest: $manifest,
        iso_builder: $iso_builder
    }' > "$OUT"

echo "build-info -> $OUT"
