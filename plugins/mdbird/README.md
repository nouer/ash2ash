# mdbird

Archive tweets/X posts as clean Markdown files with locally-saved images.

## Features

- Fetches tweet content via Playwright (no API key required)
- Downloads images at high resolution (`name=large`)
- Generates clean Markdown with YAML frontmatter
- Handles login walls, quoted tweets, engagement metrics
- Organizes output by username with separate image directories

## Prerequisites

- **Playwright plugin** must be installed and enabled in Claude Code

## Usage

```
/mdbird https://x.com/username/status/1234567890
```

Accepts both `x.com` and `twitter.com` URLs.

## Output Structure

```
mdbird/
└── {username}/
    ├── tweet-{username}-{tweet_id}.md
    └── images/
        ├── tweet-{username}-{tweet_id}_1.jpg
        └── tweet-{username}-{tweet_id}_2.jpg
```

## Markdown Format

Each archived tweet includes:

- YAML frontmatter (author, date, tweet ID, URL, archive timestamp)
- Full tweet text as blockquote
- Locally-saved images with relative paths
- Quoted tweet content (if present)
- Engagement metrics table (replies, reposts, likes, bookmarks, views)

## Edge Cases

- **Deleted/suspended tweets**: Detected and reported
- **Protected accounts**: Detected and reported
- **Login walls**: Automatically removed via JavaScript injection
- **Videos**: Thumbnail captured if available, with note linking to original
- **Failed image downloads**: Falls back to remote URL in Markdown
