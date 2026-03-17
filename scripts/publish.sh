#!/bin/bash
# 将 Obsidian vault 的博客文章同步到 git repo 并推送
# 用法: ./scripts/publish.sh [commit message]

set -e

VAULT_BLOG="/Users/yiou/Library/Mobile Documents/iCloud~md~obsidian/Documents/Quant_OS/blog/posts"
REPO_BLOG="$(dirname "$0")/../src/content/blog"

# 同步 md 文件（删除 repo 中已删除的文章）
rsync -av --delete --include="*.md" --exclude="*" \
  "$VAULT_BLOG/" "$REPO_BLOG/"

# 提交并推送
cd "$(dirname "$0")/.."
git add src/content/blog/
git status --short src/content/blog/

CHANGED=$(git diff --cached --name-only src/content/blog/ | wc -l | tr -d ' ')
if [ "$CHANGED" -eq 0 ]; then
  echo "没有变更，无需推送。"
  exit 0
fi

MSG="${1:-update blog posts}"
git commit -m "$MSG"
git push

echo "✓ 已推送 $CHANGED 个文件变更，Cloudflare Pages 将自动构建部署。"
