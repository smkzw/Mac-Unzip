#!/usr/bin/env bash
# =============================================================================
# publish_release.sh — 发布 MacUnzip / Mac解霸 到 GitHub Pro 仓库
# 默认 DRY-RUN：只做校验并打印将执行的命令，不碰网络写操作。
# 加 --yes 才真正执行 git push + gh release create（外部不可逆动作，需操作者确认）。
# 与 Scripts/package_release.sh（构建 DMG）配套，构成 构建→发布 闭环。
#
# 用法：
#   ./Scripts/publish_release.sh --version 1.0.8            # dry-run 预演
#   ./Scripts/publish_release.sh --version 1.0.8 --yes      # 真正发布
# =============================================================================
set -euo pipefail

VERSION=""; YES=false; REPO="smkzw/Mac-Unzip"; BRANCH="release"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2 ;;
    --yes)     YES=true;   shift   ;;
    --repo)    REPO="$2";  shift 2 ;;
    --branch)  BRANCH="$2"; shift 2 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done
[[ -n "$VERSION" ]] || { echo "错误: --version 必填"; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
DMG="build/MacUnzip-${VERSION}.dmg"; SHA="${DMG}.sha256"
NOTES="Distribution/RELEASE_NOTES_v${VERSION}.md"
TARGET="$(git rev-parse HEAD)"

# run: --yes 才执行，否则只打印（dry-run）
run() { if $YES; then echo ">>> $*"; "$@"; else echo "  [dry-run] $*"; fi; }

echo "================ 发布预检 v${VERSION} → ${REPO}@${BRANCH} ================"
echo "  target commit: ${TARGET}"
$YES && echo "  模式: 真实发布 (--yes)" || echo "  模式: DRY-RUN（加 --yes 才真正发布）"

echo "--- 1. 产物存在性 ---"
[[ -f "$DMG"   ]] || { echo "  缺 ${DMG}（先跑 package_release.sh --version ${VERSION}）"; exit 1; }
[[ -f "$SHA"   ]] || { echo "  缺 ${SHA}"; exit 1; }
[[ -f "$NOTES" ]] || { echo "  缺 ${NOTES}（先写 release notes）"; exit 1; }
echo "  OK: dmg / sha256 / notes 齐全"

echo "--- 2. DMG 校验和一致 ---"
expect=$(awk '{print $1}' "$SHA"); actual=$(shasum -a 256 "$DMG" | awk '{print $1}')
[[ "$expect" == "$actual" ]] || { echo "  校验和不一致 expect=$expect actual=$actual"; exit 1; }
echo "  OK: ${actual}"

echo "--- 3. 工作区无未提交修改（未跟踪文件不影响 push，不检查）---"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "  有未提交的修改，请先 commit"; exit 1
fi
echo "  OK"

echo "--- 4. push 可 fast-forward（远程不得领先本地）---"
behind=$(git rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)
[[ "$behind" == "0" ]] || { echo "  远程领先 ${behind} 个 commit，需先 pull/rebase"; exit 1; }
ahead=$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
echo "  OK: 本地领先 ${ahead} 个 commit 待推送"

echo "--- 5. 远程 tag v${VERSION} 不得已存在 ---"
if gh api "repos/${REPO}/git/refs/tags/v${VERSION}" >/dev/null 2>&1; then
  echo "  tag v${VERSION} 已存在，拒绝覆盖（如需重发请先删 tag/release）"; exit 1
fi
echo "  OK: 可创建"

echo "================ 将执行的命令 ================"
run git push origin "${BRANCH}"
# Fast-forward main to release tip (v1.0.7 convention: tag sat on main tip).
# Safe only when origin/main ⊂ HEAD (strict ancestor = zero divergence).
if git merge-base --is-ancestor origin/main HEAD 2>/dev/null; then
  echo "  origin/main ⊂ HEAD → fast-forward main"
  run git push origin "${BRANCH}:main"
else
  echo "  ⚠ origin/main 非 HEAD 祖先（diverged）→ 跳过 main 同步，需手动处理"
fi
run gh release create "v${VERSION}" --repo "${REPO}" --target "${TARGET}" \
    --title "MacUnzip v${VERSION}" --notes-file "${NOTES}" "${DMG}" "${SHA}"

if $YES; then
  echo "================ 发布后验证 ================"
  gh release view "v${VERSION}" --repo "${REPO}" \
    --json tagName,targetCommitish,assets \
    --jq '{tag:.tagName, target:.targetCommitish, assets:[.assets[].name]}'
  echo "发布完成: https://github.com/${REPO}/releases/tag/v${VERSION}"
else
  echo "================ DRY-RUN 完成：未执行任何外部写操作 ================"
  echo "确认无误后加 --yes 真正发布。"
fi
