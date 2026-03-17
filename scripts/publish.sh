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

# 检测新增的文章（推送前记录，避免 git push 后 HEAD 变化）
NEW_POSTS=$(git diff --cached --name-only --diff-filter=A src/content/blog/*.md 2>/dev/null || true)

git commit -m "$MSG"
git push

echo "✓ 已推送 $CHANGED 个文件变更，Cloudflare Pages 将自动构建部署。"

# 如果有新文章，在浏览器打开预填好内容的推文编辑框
if [ -n "$NEW_POSTS" ]; then
  echo ""
  echo "📢 发现新文章，在浏览器打开推文草稿..."
  for f in $NEW_POSTS; do
    TITLE=$(grep -m1 '^title:' "$f" | sed 's/^title:[[:space:]]*//' | tr -d '"'"'" 2>/dev/null)
    SLUG=$(basename "$f" .md)
    URL="https://blog.opentrading.tech/blog/${SLUG}/"
    if [ -n "$TITLE" ]; then
      TWEET_TEXT="📝 ${TITLE}

${URL}"
    else
      TWEET_TEXT="${URL}"
    fi
    echo "---"
    echo "$TWEET_TEXT"
    echo "---"
    # URL encode
    ENCODED=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$TWEET_TEXT")
    open "https://x.com/compose/tweet?text=${ENCODED}"
  done
  echo ""
  echo "✓ 浏览器已打开推文编辑框，审核后手动点击发送。"
fi
