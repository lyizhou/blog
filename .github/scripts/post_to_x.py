#!/usr/bin/env python3
"""
Push new blog post notifications to X.
Usage: python3 post_to_x.py src/content/blog/post1.md src/content/blog/post2.md
"""
import sys
import os
import re
import tweepy
import frontmatter

SITE = "https://blog.opentrading.tech"


def build_tweet(filepath: str) -> str | None:
    post = frontmatter.load(filepath)

    # Skip drafts
    if post.get("draft", False):
        print(f"Skipping draft: {filepath}")
        return None

    title = post.get("title", "").strip()
    description = post.get("description", "").strip()
    tags = post.get("tags", [])

    # Build URL from filename
    slug = os.path.basename(filepath).replace(".md", "")
    url = f"{SITE}/blog/{slug}/"

    # Build hashtags (max 3, alphanumeric only)
    hashtags = " ".join(
        f"#{re.sub(r'[^a-zA-Z0-9\u4e00-\u9fff]', '', tag)}"
        for tag in tags[:3]
        if tag
    )

    lines = [f"📝 {title}", "", url]
    if description:
        lines.insert(1, description)
    if hashtags:
        lines += ["", hashtags]

    tweet = "\n".join(lines)

    # X limit is 280 chars
    if len(tweet) > 280:
        lines = [f"📝 {title}", "", url]
        if hashtags:
            lines += ["", hashtags]
        tweet = "\n".join(lines)

    return tweet


def post_to_x(tweet: str) -> None:
    client = tweepy.Client(
        consumer_key=os.environ["X_API_KEY"],
        consumer_secret=os.environ["X_API_SECRET"],
        access_token=os.environ["X_ACCESS_TOKEN"],
        access_token_secret=os.environ["X_ACCESS_TOKEN_SECRET"],
    )
    response = client.create_tweet(text=tweet)
    print(f"✓ Posted tweet ID: {response.data['id']}")
    print(f"  Content: {tweet[:80]}...")


if __name__ == "__main__":
    files = [f for f in sys.argv[1:] if f.strip()]
    if not files:
        print("No files provided.")
        sys.exit(0)

    for filepath in files:
        print(f"Processing: {filepath}")
        tweet = build_tweet(filepath)
        if tweet:
            print(f"Tweet preview:\n{tweet}\n")
            post_to_x(tweet)
