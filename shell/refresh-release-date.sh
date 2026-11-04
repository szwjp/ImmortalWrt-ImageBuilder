#!/bin/sh
# 刷新 release 的发布时间, 让 release 列表页显示的日期跟随本次构建。
#
# 背景: GitHub 的 release 列表显示的是 published_at, 而该字段只在 release 从
# draft 变成 published 时才更新。CI 的常规流程只是往同一个 release 上覆盖同名
# 资产, published_at 会一直停在首次发布的时间, 页面于是显示几个月前的日期,
# 与实际最新固件对不上。
#
# 这里做一次 draft -> published 往返: published_at 刷新为当前时间, 资产不受影响。
#
# 用法: sh shell/refresh-release-date.sh <tag> [owner/repo]
#   tag        release 的 tag 名, 如 Autobuild-x86-64
#   owner/repo 仓库, 默认取环境变量 GITHUB_REPOSITORY
#
# 需要 GH_TOKEN (CI 中为 ${{ secrets.GITHUB_TOKEN }})。

set -eu

usage() {
	echo "用法: $0 <tag> [owner/repo]" >&2
	exit 1
}

tag="${1:-}"
[ -n "$tag" ] || usage

repo="${2:-${GITHUB_REPOSITORY:-}}"
[ -n "$repo" ] || usage

: "${GH_TOKEN:?必须设置 GH_TOKEN (CI 中为 \${{ secrets.GITHUB_TOKEN }})}"

# 取 release id。按 tag 直接查是主路径; 查不到时再用列表接口确认到底是
# "release 不存在"(首次构建, 正常跳过) 还是 "API 调用失败"(真错误, 必须报错),
# 否则一次网络抖动就会让刷新步骤静默失效, 日期又停在旧值。
id=$(gh api "repos/${repo}/releases/tags/${tag}" --jq '.id' 2>/dev/null) || id=""

if [ -z "$id" ]; then
	tags=$(gh api "repos/${repo}/releases?per_page=100" --jq '.[].tag_name' 2>/dev/null) || {
		echo "查询 release ${tag} 失败(API 错误), 刷新中止" >&2
		exit 1
	}
	if printf '%s\n' "$tags" | grep -Fxq "$tag"; then
		echo "查询 release ${tag} 失败(列表里有但按 tag 查不到), 刷新中止" >&2
		exit 1
	fi
	echo "release ${tag} 不存在, 跳过" >&2
	exit 0
fi

# 先转 draft, 再转回 published; 这两步就是刷新 published_at 的关键
gh api -X PATCH "repos/${repo}/releases/${id}" -F draft=true >/dev/null

# 转回 published 若失败(如瞬时 API 错误)重试一次; 仍失败才让步骤失败,
# 否则 release 会卡在 draft 状态对外不可见
if ! gh api -X PATCH "repos/${repo}/releases/${id}" -F draft=false --jq '.published_at'; then
	echo "发布 release 失败, 重试一次" >&2
	gh api -X PATCH "repos/${repo}/releases/${id}" -F draft=false --jq '.published_at'
fi
