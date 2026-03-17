---
title: "博客发文自动同步到 X：从 API 收费到免费方案"
date: 2026-03-17
tags: ["博客", "自动化", "X", "GitHub Actions", "Astro"]
draft: false
description: "为 Astro 博客搭建自动发推流程：踩过 X API 收费的坑，最终用 web intent URL 实现零成本、可审核的半自动发布方案。"
---

写完文章推送到 GitHub，博客自动构建——这一步已经很顺滑了。但还差最后一公里：让读者知道有新文章。手动复制链接去 X 发推，容易忘，也懒得做。

这篇文章记录为 Astro 博客搭建自动发推流程的完整过程，包括踩过的坑和最终方案。

## 目标

每次 `publish.sh` 推送新文章后，自动把文章标题 + 链接发到 X，或至少帮我把内容填好，我审核一下再发。

## 方案一：GitHub Actions + X API（失败）

最直觉的方案：在 GitHub Actions 里检测新增的 `.md` 文件，调用 X API 发推。

### 工作流

```yaml
# .github/workflows/post-to-x.yml
on:
  push:
    branches: [main]
    paths:
      - 'src/content/blog/**.md'

jobs:
  post-to-x:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2

      - name: Find newly added blog posts
        id: new-posts
        run: |
          NEW_FILES=$(git diff --name-only --diff-filter=A HEAD~1 HEAD \
            -- 'src/content/blog/*.md' | tr '\n' ' ')
          echo "files=$NEW_FILES" >> $GITHUB_OUTPUT

      - name: Post to X
        env:
          X_API_KEY: ${{ secrets.X_API_KEY }}
          X_API_SECRET: ${{ secrets.X_API_SECRET }}
          X_ACCESS_TOKEN: ${{ secrets.X_ACCESS_TOKEN }}
          X_ACCESS_TOKEN_SECRET: ${{ secrets.X_ACCESS_TOKEN_SECRET }}
        run: |
          python3 .github/scripts/post_to_x.py ${{ steps.new-posts.outputs.files }}
```

Python 脚本用 tweepy 读取文章 frontmatter，拼出推文：

```python
def build_tweet(filepath: str) -> str:
    post = frontmatter.load(filepath)
    title = post.get("title", "").strip()
    slug = os.path.basename(filepath).replace(".md", "")
    url = f"https://blog.opentrading.tech/blog/{slug}/"
    return f"📝 {title}\n\n{url}"
```

### 遇到的问题

**第一个坑：App 权限是 Read-only。** X Developer Portal 默认只读，需要手动改成 Read+Write，改完要重新生成 Access Token，否则旧 Token 不带写权限。

**第二个坑：402 Payment Required。** X Free tier（Basic 套餐）不允许通过 API 发推，必须付费升级到 Basic+ 或以上（$100/月起）。

```
tweepy.errors.Forbidden: 403 Forbidden
453 - You currently have Essential access which includes access to Twitter API v2 endpoints only.
```

GitHub Actions 方案到这里宣告失败——不想为发推付 $100/月。

## 方案二：opencli（部分可用）

[opencli](https://github.com/jackwener/opencli) 通过 Playwright MCP Bridge Chrome 扩展复用浏览器登录状态，绕过 API 限制。

安装：

```bash
npm install -g @jackwener/opencli
```

还需要在 Chrome 里安装 **Playwright MCP Bridge** 扩展，获取 token 后：

```bash
export PLAYWRIGHT_MCP_EXTENSION_TOKEN=your_token_here
opencli twitter post --text "测试推文"
```

这个方案可以工作，但有两个顾虑：

1. **不可审核**：脚本直接发推，没有预览机会
2. **依赖本机 Chrome**：服务器上无法运行，只能在本地执行

对于博客发推这个场景，我希望在正式发出前能看一眼内容——毕竟文章标题和链接拼出来的效果，还是想确认一下。

## 最终方案：X Web Intent URL

X 提供了一个 [web intent](https://developer.x.com/en/docs/twitter-for-websites/tweet-button/guides/web-intent) 接口，可以在浏览器里打开一个预填好内容的推文编辑框：

```
https://x.com/compose/tweet?text=预填内容
```

用户看到已填好的推文，确认没问题后手动点 Post。**零 API 费用，有审核环节，体验和直接发推差不多。**

在 `publish.sh` 里加几行：

```bash
# 检测新增文章
NEW_POSTS=$(git diff --cached --name-only --diff-filter=A src/content/blog/*.md 2>/dev/null || true)

git commit -m "$MSG"
git push

# 新文章 → 打开浏览器推文编辑框
if [ -n "$NEW_POSTS" ]; then
  for f in $NEW_POSTS; do
    TITLE=$(grep -m1 '^title:' "$f" | sed 's/^title:[[:space:]]*//' | tr -d '"'"'" 2>/dev/null)
    SLUG=$(basename "$f" .md)
    URL="https://blog.opentrading.tech/blog/${SLUG}/"
    TWEET_TEXT="📝 ${TITLE}

${URL}"
    # URL encode 后在浏览器打开
    ENCODED=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$TWEET_TEXT")
    open "https://x.com/compose/tweet?text=${ENCODED}"
  done
fi
```

效果：`./scripts/publish.sh` 执行后，终端打印文章变更情况，浏览器自动弹出填好内容的 X 编辑框，我看一眼点发送就完成了。

## 完整发布流程

```
Obsidian 写文章
      ↓
./scripts/publish.sh
      ↓
rsync → src/content/blog/
      ↓
git commit + push
      ↓
Cloudflare Pages 自动构建部署
      ↓
浏览器弹出预填推文（手动确认发送）
```

整套流程一条命令搞定，发推这步保留了人工审核，避免自动化出错直接发出去尴尬内容。

## 小结

| 方案 | 成本 | 自动化程度 | 可审核 |
|------|------|-----------|--------|
| X API + GitHub Actions | $100/月 | 全自动 | ✗ |
| opencli | 免费 | 全自动 | ✗ |
| Web Intent URL | 免费 | 半自动 | ✓ |

对于个人博客这个低频场景（一周最多几篇），半自动足够用，完全不值得付 API 费用。Web Intent 方案简单、可靠、可控，是目前最合适的选择。
