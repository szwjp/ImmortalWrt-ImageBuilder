#!/bin/sh
# CI 工作流的构建稳定性约定断言(纯 shell, 不联网, 秒级)
#
# 用法: sh shell/tests/workflow-ci-test.sh
# 退出码 0 = 全部通过; 1 = 有失败
#
# 这些约定改坏了不会让任何单个脚本报错, 只会在某次构建里以"卡住/互相覆盖/
# 日志泄露/release 消失"的形式出现, 而且往往要等到下一次发布才发现。
# 所以把每一条都做成硬断言。
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
WORKFLOW="$REPO_ROOT/.github/workflows/build-x86-64.yml"
CLEAN="$REPO_ROOT/.github/workflows/clean-workflow.yml"
TEST_WF="$REPO_ROOT/.github/workflows/test.yml"
BUILD_SH="$REPO_ROOT/x86-64/build.sh"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ✅ $1"; }
bad() { fail=$((fail + 1)); echo "  ❌ $1"; }

for f in "$WORKFLOW" "$CLEAN" "$TEST_WF" "$BUILD_SH"; do
  [ -f "$f" ] || { echo "❌ 找不到 $f" >&2; exit 1; }
done

# ================================================================
# 1. 并发控制: release tag 是固定的, 并发跑会互相覆盖同名资产
# ================================================================
if grep -q '^concurrency:' "$WORKFLOW" && grep -q 'cancel-in-progress: false' "$WORKFLOW"; then
  ok "构建 workflow 有串行化的 concurrency(且不取消进行中的构建)"
else
  bad "构建 workflow 缺少 concurrency 或会 cancel-in-progress: 并发 dispatch 会互相覆盖 release 资产"
fi

# ================================================================
# 2. 超时: 没有 timeout 时 docker/apt 挂起会按默认 360 分钟占机
# ================================================================
n_timeout=$(grep -c '^    timeout-minutes:' "$WORKFLOW" || true)
if [ "${n_timeout:-0}" -ge 2 ]; then
  ok "两个 job 都设了 timeout-minutes($n_timeout 处)"
else
  bad "构建 workflow 的 job 没有都设 timeout-minutes(实际 $n_timeout 处)"
fi
if grep -q '^    timeout-minutes:' "$CLEAN"; then
  ok "清理 workflow 设了 timeout-minutes"
else
  bad "清理 workflow 没有 timeout-minutes"
fi
if grep -q '^    timeout-minutes:' "$TEST_WF"; then
  ok "测试 workflow 设了 timeout-minutes"
else
  bad "测试 workflow 没有 timeout-minutes"
fi

# ================================================================
# 3. ImageBuilder 镜像按 digest 钉死(与 ISO 链路 debian:buster 的钉法一致)
# ================================================================
for v in 25.12.0 25.12.1 25.12.2; do
  if grep -qE "^\s+${v}\) digest=\"sha256:[0-9a-f]{64}\"" "$WORKFLOW"; then
    ok "ImageBuilder digest 已钉: $v"
  else
    bad "ImageBuilder digest 缺失: $v(该版本构建会被拒绝)"
  fi
done
if grep -qF 'immortalwrt/imagebuilder@${{ steps.ib.outputs.digest }}' "$WORKFLOW"; then
  ok "docker run 使用 digest 而不是 tag"
else
  bad "docker run 没有使用 digest"
fi
if grep -qE 'imagebuilder:x86-64' "$WORKFLOW"; then
  bad "workflow 仍按 tag 拉 ImageBuilder 镜像, 产物不可复现"
else
  ok "没有按 tag 拉 ImageBuilder 镜像的残留"
fi

# ================================================================
# 4. 凭据不进日志: 必须走 env:, 且引用时加引号
# ================================================================
for key in LUCI_VERSION PROFILE INCLUDE_DOCKER ENABLE_PPPOE PPPOE_ACCOUNT PPPOE_PASSWORD; do
  if grep -qF "          ${key}: \${{" "$WORKFLOW"; then
    ok "凭据/参数经 env 传入: $key"
  else
    bad "缺少 env 传参: $key(build.sh 会读到空值)"
  fi
done
if grep -qF -- '-e PPPOE_PASSWORD="$PPPOE_PASSWORD"' "$WORKFLOW" \
   && grep -qF -- '-e PPPOE_ACCOUNT="$PPPOE_ACCOUNT"' "$WORKFLOW"; then
  ok "凭据引用方式安全(加引号, 不做分词)"
else
  bad "凭据引用没有加引号, 含空格/引号的值会被 shell 拆错"
fi
# 关键: 脚本里不能再出现 ${{ inputs.pppoe_password }} 这种内联 ——
# Actions 会把 run: 脚本全文回显到日志, 内联等于把密码明文写进日志。
if grep -qF 'PPPOE_PASSWORD=${{' "$WORKFLOW" || grep -qF 'PPPOE_ACCOUNT=${{' "$WORKFLOW"; then
  bad "workflow 仍把 PPPoE 凭据内联进脚本, 会以明文出现在运行日志里"
else
  ok "PPPoE 凭据没有内联进脚本(不会被日志回显)"
fi

# ================================================================
# 5. 发布产物: 必须带校验和与包清单
# ================================================================
if grep -q 'sha256sum' "$WORKFLOW"; then
  ok "发布资产包含 sha256 校验和"
else
  bad "发布资产没有 sha256 校验和, 下载方无法校验完整性"
fi
if grep -qF '.manifest' "$WORKFLOW"; then
  ok "发布资产包含 ImageBuilder 的 .manifest(包清单)"
else
  bad "发布资产没有 .manifest, 看不到固件内装了哪些包"
fi

# ================================================================
# 6. release 兜底: draft 往返失败后必须能被捞回来
# ================================================================
if grep -qF -- '--ensure-published' "$WORKFLOW"; then
  ok "workflow 有 draft 兜底发布步骤"
else
  bad "workflow 没有兜底发布: 日期刷新中途失败会把 release 卡在 draft"
fi
if grep -qF 'always()' "$WORKFLOW"; then
  ok "兜底步骤用 always() 保证失败路径也会执行"
else
  bad "兜底步骤没用 always(), 前一步失败时不会执行"
fi

# ================================================================
# 7. profile 输入的下限: 太小会在打包阶段才失败
# ================================================================
if grep -qF 'profile" -lt 256' "$WORKFLOW"; then
  ok "profile 有下限校验"
else
  bad "profile 没有下限校验, 传 1MB 会在 deep 阶段才失败"
fi

# ================================================================
# 8. push/PR 也要跑测试: 只在手动构建里跑等于没有回归保护
# ================================================================
if grep -qE '^\s+push:' "$TEST_WF" && grep -qE '^\s+pull_request:' "$TEST_WF"; then
  ok "测试 workflow 在 push / pull_request 上触发"
else
  bad "测试 workflow 没有在 push/pull_request 上触发, 规则写坏了没人发现"
fi
if grep -q 'sh shell/tests/run-all.sh' "$TEST_WF"; then
  ok "测试 workflow 跑的是同一套 run-all.sh"
else
  bad "测试 workflow 没有调用 run-all.sh, 与本地/构建流程不一致"
fi

# ================================================================
# 9. action 运行时: Node20 已被弃用(runner 会强行拉起到 Node24)
# ================================================================
if grep -qE 'actions/checkout@v[0-4]$|action-gh-release@v2' "$WORKFLOW" "$TEST_WF"; then
  bad "仍在使用 Node20 时代的 action 版本(checkout@v4 或 action-gh-release@v2)"
else
  ok "action 版本已避开 Node20 弃用线"
fi

# ================================================================
# 10. 镜像与包集合的接口: build.sh 必须真的消费这些环境变量
# ================================================================
for key in LUCI_VERSION PROFILE INCLUDE_DOCKER ENABLE_PPPOE PPPOE_ACCOUNT PPPOE_PASSWORD; do
  # 两种写法都算: $KEY 与 ${KEY}/${KEY:-} / ${KEY:+...}
  if grep -q "\$${key}" "$BUILD_SH" || grep -q "\${${key}" "$BUILD_SH"; then
    ok "build.sh 消费 $key"
  else
    bad "build.sh 没有使用 $key, workflow 传了也白传"
  fi
done

echo
echo "workflow-ci-test: 通过 $pass, 失败 $fail"
[ "$fail" -eq 0 ] || exit 1
