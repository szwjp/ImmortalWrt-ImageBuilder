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
# 用法:
#   sh shell/refresh-release-date.sh <tag> [owner/repo]
#       做 draft -> published 往返, 刷新 published_at。
#   sh shell/refresh-release-date.sh --ensure-published <tag> [owner/repo]
#       只保证 release 处于 published 状态(已经是就什么都不做)。
#       用于 CI 的兜底步骤: 上面那次往返若中途失败/被取消, release 会卡在
#       draft 状态对外不可见, 这个模式负责把它捞回来。
#
#   tag        release 的 tag 名, 如 Autobuild-x86-64
#   owner/repo 仓库, 默认取环境变量 GITHUB_REPOSITORY
#
# 需要 GH_TOKEN (CI 中为 ${{ secrets.GITHUB_TOKEN }})。

set -u

usage() {
	echo "用法: $0 [--ensure-published] <tag> [owner/repo]" >&2
	exit 1
}

mode="refresh"
case "${1:-}" in
	--ensure-published) mode="ensure"; shift ;;
	--help|-h) usage ;;
esac

tag="${1:-}"
[ -n "$tag" ] || usage

repo="${2:-${GITHUB_REPOSITORY:-}}"
[ -n "$repo" ] || usage

: "${GH_TOKEN:?必须设置 GH_TOKEN (CI 中为 \${{ secrets.GITHUB_TOKEN }})}"

# 取 release id。按 tag 直接查是主路径; 查不到时再用列表接口确认到底是
# "release 不存在"(首次构建, 正常跳过) 还是 "API 调用失败"(真错误, 必须报错),
# 否则一次网络抖动就会让刷新步骤静默失效, 日期又停在旧值。
#
# 返回值: 0 = 找到(id 由 stdout 输出); 1 = release 不存在; 2 = API 故障
find_release_id() {
	id=$(gh api "repos/${repo}/releases/tags/${tag}" --jq '.id' 2>/dev/null) || id=""
	if [ -n "$id" ]; then
		printf '%s' "$id"
		return 0
	fi

	tags=$(gh api "repos/${repo}/releases?per_page=100" --jq '.[].tag_name' 2>/dev/null) || {
		echo "查询 release ${tag} 失败(API 错误), 刷新中止" >&2
		return 2
	}
	if printf '%s\n' "$tags" | grep -Fxq "$tag"; then
		echo "查询 release ${tag} 失败(列表里有但按 tag 查不到), 刷新中止" >&2
		return 2
	fi
	echo "release ${tag} 不存在, 跳过" >&2
	return 1
}

# 发布 release。瞬时 API 错误重试, 仍失败则报错 —— 否则 release 会卡在 draft。
publish_release() {
	_attempt=1
	while [ "$_attempt" -le 3 ]; do
		if gh api -X PATCH "repos/${repo}/releases/${pub_id}" -F draft=false --jq '.published_at'; then
			return 0
		fi
		echo "发布 release ${tag} 失败(第 ${_attempt} 次), 重试" >&2
		_attempt=$((_attempt + 1))
		sleep 1
	done
	echo "发布 release ${tag} 失败: 它仍是 draft 状态(对外不可见), 请手动发布" >&2
	return 1
}

resolved=$(find_release_id)
rc=$?
if [ "$rc" -eq 1 ]; then
	exit 0
elif [ "$rc" -ne 0 ]; then
	exit 1
fi
id="$resolved"

if [ "$mode" = "ensure" ]; then
	draft=$(gh api "repos/${repo}/releases/${id}" --jq '.draft' 2>/dev/null) || draft=""
	if [ "$draft" = "false" ]; then
		echo "release ${tag} 已是 published, 无需处理" >&2
		exit 0
	fi
	# draft=true, 或查询失败(取不到状态)—— 两种情况都尝试发布一次:
	# PATCH 是幂等的, 状态未知时宁可多打一次 API, 也不要让 release 留在 draft。
	echo "release ${tag} 卡在 draft, 正在重新发布" >&2
	pub_id="$id"
	publish_release || exit 1
	exit 0
fi

# 先转 draft, 再转回 published; 这两步就是刷新 published_at 的关键。
# 转 draft 这一步失败就没法刷新日期, 直接报错(否则会"看起来成功、日期没变")。
if ! gh api -X PATCH "repos/${repo}/releases/${id}" -F draft=true >/dev/null; then
	echo "把 release ${tag} 转成 draft 失败, 刷新中止" >&2
	exit 1
fi
pub_id="$id"
publish_release || exit 1
