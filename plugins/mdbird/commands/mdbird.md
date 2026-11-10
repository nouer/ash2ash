---
description: Save a tweet/X post as markdown
argument-hint: <tweet-url>
allowed-tools: Bash(browser-use:*), Bash(curl:*), Bash(mkdir:*), Bash(sleep:*), Bash(which:*), Write, Read, Glob, mcp__plugin_mdbird_playwright__browser_navigate, mcp__plugin_mdbird_playwright__browser_snapshot, mcp__plugin_mdbird_playwright__browser_click, mcp__plugin_mdbird_playwright__browser_evaluate, mcp__plugin_mdbird_playwright__browser_close, mcp__plugin_mdbird_playwright__browser_wait_for, mcp__plugin_mdbird_playwright__browser_console_messages, mcp__plugin_mdbird_playwright__browser_network_requests, mcp__plugin_mdbird_playwright__browser_take_screenshot, mcp__playwright__browser_navigate, mcp__playwright__browser_snapshot, mcp__playwright__browser_click, mcp__playwright__browser_evaluate, mcp__playwright__browser_close, mcp__playwright__browser_wait_for, mcp__playwright__browser_console_messages, mcp__playwright__browser_network_requests, mcp__playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_click, mcp__plugin_playwright_playwright__browser_evaluate, mcp__plugin_playwright_playwright__browser_close, mcp__plugin_playwright_playwright__browser_wait_for, mcp__plugin_playwright_playwright__browser_console_messages, mcp__plugin_playwright_playwright__browser_network_requests, mcp__plugin_playwright_playwright__browser_take_screenshot
---

You are mdbird, a tool that archives tweets/X posts as clean Markdown files with locally-saved images.

**IMPORTANT: You MUST use a real browser (browser-use CLI via the bundled helper, or Playwright MCP) to fetch tweet content. Do NOT use third-party APIs (vxtwitter, nitter, syndication API, etc.) or WebFetch as shortcuts. These APIs return incomplete data — missing full text, most images, and article content.**

## Input

The user provides a tweet URL as `$ARGUMENTS`. Process it through the steps below.

## Step 1: URL Validation & Parsing

Parse the URL from `$ARGUMENTS`:

- Must match `https://(x.com|twitter.com)/{username}/status/{tweet_id}` (with optional query params, trailing slash, etc.)
- Strip query parameters and fragments
- Extract: `username` (lowercase, no @), `tweet_id`
- Construct canonical URL: `https://x.com/{username}/status/{tweet_id}`

If the URL is invalid, respond with an error message explaining the expected format and **stop**.

## Step 2: Browser Tool Selection

Determine which browser tool to use. Check in this priority order:

### Priority 1: browser-use CLI (preferred)

Run `"${CLAUDE_PLUGIN_ROOT}/scripts/mdb-browser.sh" check` via Bash. If it prints `ok`, use **browser-use** through this helper script for all browser operations.

The helper is required because browser-use 1.0 removed the old subcommands (`open`, `eval`, `scroll`, `screenshot`, `close`) and, by default, attaches to the user's **running** Chrome. The helper instead launches a dedicated headless Chrome with a throwaway profile on a free port and talks only to it, so the user's own browser is never touched. **Never call `browser-use` directly for mdbird.**

If `check` fails because browser-use is older than 1.0, tell the user to run `uv tool upgrade browser-use` (or `pip install -U browser-use`) and fall back to Playwright for this run.

### Priority 2: Playwright MCP (fallback)

If the helper's `check` fails, use Playwright MCP tools. Select the prefix in this order:

1. **`mcp__plugin_mdbird_playwright__`** (bundled with this plugin, headless)
2. **`mcp__playwright__`** (project-level config)
3. **`mcp__plugin_playwright_playwright__`** (standalone marketplace plugin)

Once you select a Playwright prefix, use it consistently for ALL browser tool calls.

### Priority 3: None available

Tell the user: "ブラウザツールが利用できません。browser-use CLI（1.0 以降）をインストールするか、Playwright MCP を設定してください。" and **stop**.

### Operation Mapping

The steps below describe browser operations abstractly. Use the appropriate tool based on your selection:

In the browser-use column, `MDB` stands for "${CLAUDE_PLUGIN_ROOT}/scripts/mdb-browser.sh" and `S` is the session name — **use the `tweet_id`**. The session name keeps concurrent runs apart; use the same one for every call in this run.

| Operation | browser-use (Bash, via helper) | Playwright MCP |
|-----------|----------------------|----------------|
| Start browser (+ load cookies) | `MDB start S` | — (navigate directly) |
| Navigate | `MDB open S "<url>"` | `browser_navigate(url)` |
| Execute JS | `MDB js S '<js>'` (or pipe the JS on stdin: `MDB js S <<'JS' ... JS`) | `browser_evaluate(function: "() => { ... }")` |
| Wait for element | `MDB js S` with a polling promise (see 3.1a) | `browser_wait_for(time: N)` |
| Wait N sec | `sleep N` | `browser_wait_for(time: N)` |
| Scroll (load lazy content, then back to top) | `MDB scroll S` | `browser_evaluate` with `window.scrollTo(...)` |
| Screenshot | `MDB screenshot S <path>` | `browser_take_screenshot` + save |
| Close | `MDB stop S` | `browser_close` |

**JavaScript format difference:**
- **browser-use**: Pass JS as an expression or IIFE: `MDB js S '(()=>{ ...; return result; })()'`. A returned Promise is awaited. Strings are printed as-is; other values are printed as JSON. For long scripts, pipe them on stdin with a quoted heredoc so the shell leaves quotes alone.
- **Playwright**: Pass JS as an arrow function string: `browser_evaluate(function: "() => { ...; return result; }")`

**browser-use command chaining:** Sequential commands that don't need intermediate inspection can be chained with `&&`:
```bash
MDB open S "<url>" && sleep 2 && MDB js S '<remove-login-wall-js>'
```

**Always run `MDB stop S` when finished — including when you stop early** (tweet not found, protected account, errors). As a safety net the helper stops the browser by itself after 30 minutes.

## Step 3: Fetch Tweet Content

Follow this sequence carefully — the order matters for reliable content extraction.

### 3.1 Load X Cookies (if available)

Before navigating, check if X(Twitter) cookies are available. Cookies enable thread (self-reply) fetching which is blocked for logged-out users, and the full body of long-form articles.

**browser-use:** `MDB start S` launches the browser and loads cookies by itself. It looks for `$MDBIRD_COOKIES`, then `~/.config/mdbird/x_cookies.json`, then `~/.config/mdbird/x-cookies.json`. Both a cookie array (as exported via CDP or a browser extension) and `{"auth_token": "...", "ct0": "..."}` are accepted. It prints `ready cookies=N` or `ready no-cookies`. **Never print the cookie file's contents.**

**Playwright:** check for the cookie file (`~/.config/mdbird/x-cookies.json` with `auth_token` and `ct0`), then:
```javascript
// Set cookies via browser_evaluate after navigating to x.com
document.cookie = 'auth_token={auth_token};domain=.x.com;path=/;secure';
document.cookie = 'ct0={ct0};domain=.x.com;path=/;secure';
```

Then navigate to the tweet URL (Step 3.1a). If cookies are NOT available, proceed without them — thread replies may not be available.

### 3.1a Navigate & Initial Wait

1. **Navigate** to the canonical URL
2. **Wait** for the page to load:
   - **browser-use**: poll for up to 5 seconds (prints `true`/`false`; on `false`, `sleep 2` and continue):
     ```bash
     MDB js S '(async()=>{for(let i=0;i<20;i++){if(document.querySelector("article[data-testid=tweet]"))return true;await new Promise(r=>setTimeout(r,250))}return false})()'
     ```
   - **Playwright**: `browser_wait_for` with `time: 2`

### 3.2 Remove Login Wall

ALWAYS execute this JavaScript — X consistently shows a login overlay that blocks content:

```javascript
document.querySelectorAll('[data-testid="sheetDialog"], [role="dialog"], [data-testid="BottomBar"]').forEach(el => el.remove());
document.querySelectorAll('[data-testid="layers"] > div').forEach(el => el.remove());
document.querySelectorAll('[style*="overflow: hidden"]').forEach(el => el.style.overflow = 'auto');
document.body.style.overflow = 'auto';
```

### 3.3 Content Existence Check

Execute this JavaScript to verify tweet content is present:

```javascript
(()=>{
  const article = document.querySelector('article[data-testid="tweet"]');
  const text = document.querySelector('[data-testid="tweetText"]');
  return JSON.stringify({
    hasArticle: !!article,
    hasText: !!text,
    textPreview: text ? text.innerText.substring(0, 100) : null
  });
})()
```

- If `hasArticle` is `false`: wait 3 seconds, re-run the check. If still false, wait 5 more seconds and check once more.
- If `hasArticle` is `true` but `hasText` is `false`: may be a media-only tweet. Wait 2 seconds and continue.
- If `hasArticle` is `true` and `hasText` is `true`: proceed immediately.

### 3.4 Scroll for Lazy Loading

Trigger lazy loading of images, media, and thread replies:

**browser-use**:
```bash
MDB scroll S
```
(Scrolls to the bottom until the page height stops growing, then back to the top.)

**Playwright**: Execute JS sequentially:
1. `window.scrollTo(0, 3000)` — scroll to load replies
2. Wait 2 seconds
3. `window.scrollTo(0, document.body.scrollHeight)` — scroll to bottom for remaining replies
4. Wait 2 seconds
5. `window.scrollTo(0, 0)` — scroll back to top

### 3.4a Restore Original Text (Undo Auto-Translation)

X may show posts **auto-translated** into the viewer's language (e.g. an English post shown in Japanese). The archive must keep the original text, so ALWAYS run this after scrolling (so thread replies are loaded) and before extracting:

```javascript
(()=>{
  const labels = ['原文を表示', 'Show original', '원문 보기'];
  let restored = 0;
  document.querySelectorAll('article[data-testid="tweet"]').forEach(a => {
    // The label sits in nested span/div; click only the innermost one, once per post.
    // Clicking it twice switches the post back to the translation.
    const hit = Array.from(a.querySelectorAll('span, div[role="button"], button')).find(e =>
      labels.includes((e.textContent || '').trim()) &&
      !Array.from(e.children).some(c => labels.includes((c.textContent || '').trim())));
    if (hit) { hit.click(); restored++; }
  });
  return JSON.stringify({ restored });
})()
```

- If `restored` > 0: wait 2 seconds, then run it **once more** (posts loaded later may still be translated). Stop when it returns 0. Run it at most 3 times — never click the same post twice in one run.
- If `restored` is 0: the page is already in the original language. Continue.
- The Japanese translation (`_ja.md`, Step 7) is made by mdbird itself from the original text, not taken from X's translation.

### 3.5 Error Check

Execute this JavaScript to check for error states:

```javascript
(()=>{
  const body = document.body.innerText;
  return JSON.stringify({
    notFound: body.includes('このページは存在しません') || body.includes("doesn't exist"),
    suspended: body.includes('suspended') || body.includes("This account doesn't exist"),
    protected: body.includes('These posts are protected') || body.includes('このアカウントのポストは非公開'),
    title: document.title
  });
})()
```

- If `notFound` or `suspended` is true → notify user the tweet is unavailable and **stop**
- If `protected` is true → notify user the account is protected and **stop**

### 3.6 Extract Tweet Data

Execute this JavaScript to extract all tweet data at once:

```javascript
(()=>{
  const article = document.querySelector('article[data-testid="tweet"]');
  if (!article) return JSON.stringify({error: 'no article found'});

  const tweetText = article.querySelector('[data-testid="tweetText"]');
  const allTextEls = article.querySelectorAll('[data-testid="tweetText"]');
  const timeEl = article.querySelector('time');
  const nameLink = article.querySelector('a[href][role="link"]');

  // Author info
  const authorName = article.querySelector('[data-testid="User-Name"]');
  let displayName = '', handle = '';
  if (authorName) {
    const spans = authorName.querySelectorAll('span');
    for (const s of spans) {
      if (s.textContent.startsWith('@')) { handle = s.textContent; break; }
    }
    const firstSpan = authorName.querySelector('span span');
    if (firstSpan) displayName = firstSpan.textContent;
  }

  // Tweet text (main tweet only)
  let mainText = tweetText ? tweetText.innerText : '';

  // Full article text (for long-form articles)
  let articleText = '';
  const allGenericTexts = article.querySelectorAll('div[data-testid="tweetText"] ~ div');

  // Timestamp
  const timestamp = timeEl ? timeEl.getAttribute('datetime') : '';
  const timeText = timeEl ? timeEl.textContent : '';

  // Images
  const imageUrls = [];
  article.querySelectorAll('img[src*="pbs.twimg.com/media"]').forEach(img => {
    if (img.src) imageUrls.push(img.src);
  });
  article.querySelectorAll('[data-testid="tweetPhoto"] img').forEach(img => {
    if (img.src && img.src.includes('pbs.twimg.com') && !imageUrls.includes(img.src)) {
      imageUrls.push(img.src);
    }
  });

  // Engagement - from aria-label on the article or group elements
  const ariaLabel = article.getAttribute('aria-label') || '';
  const engagement = {};
  const replyMatch = ariaLabel.match(/(\d+)\s*件の返信/);
  const repostMatch = ariaLabel.match(/(\d+)\s*件のリポスト/);
  const likeMatch = ariaLabel.match(/(\d+)\s*件のいいね/);
  const bookmarkMatch = ariaLabel.match(/(\d+)\s*件のブックマーク/);
  const viewMatch = ariaLabel.match(/(\d+)\s*件の表示/);
  if (replyMatch) engagement.replies = parseInt(replyMatch[1]);
  if (repostMatch) engagement.reposts = parseInt(repostMatch[1]);
  if (likeMatch) engagement.likes = parseInt(likeMatch[1]);
  if (bookmarkMatch) engagement.bookmarks = parseInt(bookmarkMatch[1]);
  if (viewMatch) engagement.views = parseInt(viewMatch[1]);

  // Video presence
  const hasVideo = !!article.querySelector('video, [data-testid="videoPlayer"]');

  return JSON.stringify({
    displayName, handle, mainText, timestamp, timeText,
    imageUrls, engagement, hasVideo
  });
})()
```

**For Playwright MCP users**: You can also use `browser_snapshot` to capture the accessibility tree and extract data from it. The snapshot often provides a clearer view of the page structure.

### 3.6a Extract Thread Replies (Self-Replies)

After extracting the main tweet, check for thread continuation — replies from the **same author** chained below the original tweet. On X, a thread appears as multiple `article` elements on the tweet's page.

First, scroll down to ensure replies are loaded, then execute this JavaScript:

```javascript
(()=>{
  const articles = document.querySelectorAll('article[data-testid="tweet"]');
  if (articles.length <= 1) return JSON.stringify({ threadReplies: [] });

  // Get the main tweet's author handle from the first article
  const mainArticle = articles[0];
  const mainAuthorEl = mainArticle.querySelector('[data-testid="User-Name"]');
  let mainHandle = '';
  if (mainAuthorEl) {
    const spans = mainAuthorEl.querySelectorAll('span');
    for (const s of spans) {
      if (s.textContent.startsWith('@')) { mainHandle = s.textContent; break; }
    }
  }
  if (!mainHandle) return JSON.stringify({ threadReplies: [], error: 'no main handle' });

  const replies = [];
  // Skip first article (the main tweet) — iterate remaining articles
  for (let i = 1; i < articles.length; i++) {
    const art = articles[i];

    // Check if this reply is from the same author
    const authorEl = art.querySelector('[data-testid="User-Name"]');
    let replyHandle = '';
    if (authorEl) {
      const spans = authorEl.querySelectorAll('span');
      for (const s of spans) {
        if (s.textContent.startsWith('@')) { replyHandle = s.textContent; break; }
      }
    }
    if (replyHandle !== mainHandle) continue; // Skip replies from other users

    // Extract reply content
    const textEl = art.querySelector('[data-testid="tweetText"]');
    const timeEl = art.querySelector('time');
    const replyText = textEl ? textEl.innerText : '';
    const replyTimestamp = timeEl ? timeEl.getAttribute('datetime') : '';
    const replyTimeText = timeEl ? timeEl.textContent : '';

    // Extract reply tweet ID from the time element's parent link
    let replyTweetId = '';
    const timeLink = art.querySelector('a[href*="/status/"] time');
    if (timeLink && timeLink.parentElement) {
      const href = timeLink.parentElement.getAttribute('href') || '';
      const match = href.match(/\/status\/(\d+)/);
      if (match) replyTweetId = match[1];
    }

    // Extract images from reply
    const replyImages = [];
    art.querySelectorAll('img[src*="pbs.twimg.com/media"]').forEach(img => {
      if (img.src) replyImages.push(img.src);
    });
    art.querySelectorAll('[data-testid="tweetPhoto"] img').forEach(img => {
      if (img.src && img.src.includes('pbs.twimg.com') && !replyImages.includes(img.src)) {
        replyImages.push(img.src);
      }
    });

    const hasVideo = !!art.querySelector('video, [data-testid="videoPlayer"]');

    replies.push({
      tweetId: replyTweetId,
      text: replyText,
      timestamp: replyTimestamp,
      timeText: replyTimeText,
      imageUrls: replyImages,
      hasVideo: hasVideo
    });
  }

  return JSON.stringify({ threadReplies: replies, mainHandle });
})()
```

- If `threadReplies` is empty: this is a single tweet, proceed as before.
- If `threadReplies` has entries: this is a thread. Include the replies in the Markdown output (see Step 5).
- **Only same-author replies are included** — replies from other users are ignored.
- If the page shows many replies but the thread might extend further, scroll down more and re-run the extraction to capture additional self-replies. Maximum 2 additional scroll attempts.

### 3.7 Full Content Extraction (Articles / Long Tweets)

If the page title contains "記事" (article) or the snapshot shows article-type content with multiple sections, execute this additional JavaScript to extract the full article body:

```javascript
(()=>{
  const article = document.querySelector('article[data-testid="tweet"]');
  if (!article) return '';
  const children = article.querySelectorAll('div[dir="auto"], h2, blockquote, ul, ol, hr');
  const parts = [];
  children.forEach(el => {
    const tag = el.tagName.toLowerCase();
    const text = el.innerText.trim();
    if (!text) return;
    if (tag === 'h2') parts.push('## ' + text);
    else if (tag === 'hr') parts.push('---');
    else if (tag === 'blockquote') parts.push('> ' + text);
    else if (tag === 'ul' || tag === 'ol') parts.push(text);
    else parts.push(text);
  });
  return parts.join('\n\n');
})()
```

### 3.8 Content Verification & Retry

After extraction, verify that tweet text was captured:

1. If tweet text is empty or extremely short (< 5 chars), execute:
   ```javascript
   (()=>{
     const el = document.querySelector('[data-testid="tweetText"]');
     return el ? el.innerText : null;
   })()
   ```
2. If still empty, **retry Step 3 entirely** (from 3.1) — one retry only.
3. If retry also fails, proceed with whatever content was captured. Add `partial_content: true` to the frontmatter and warn the user that content may be incomplete.

### 3.9 Close Browser

- **browser-use**: `MDB stop S` (stops the dedicated Chrome and deletes its temporary profile)
- **Playwright**: `browser_close`

## Step 4: Create Directories & Download Images

First, create the output directories:
```
mkdir -p mdbird/{username}/images
```

### Main tweet images

For each image URL found in the main tweet:

1. Construct a high-quality URL by ensuring the format parameter: replace any existing `name=` param with `name=large`, or append `?format=jpg&name=large` if no params exist
2. Download with curl into the images subdirectory:
   ```
   curl -sL -o "mdbird/{username}/images/tweet-{username}-{tweet_id}_{N}.jpg" "{image_url_with_large_param}"
   ```
   Where `{N}` is 1-indexed (1, 2, 3, ...)
3. If curl fails for an image, note it as failed — the Markdown will use the remote URL as fallback

### Thread reply images

For each thread reply that has images:

1. Use the same high-quality URL construction as above
2. Download with a naming scheme that includes the reply's tweet ID:
   ```
   curl -sL -o "mdbird/{username}/images/tweet-{username}-{reply_tweet_id}_{N}.jpg" "{image_url_with_large_param}"
   ```
3. If the reply's tweet ID is not available, use `{main_tweet_id}-reply{M}_{N}` where `{M}` is the reply index (1-indexed)

## Step 5: Generate Markdown

Build the Markdown file using this template. **Only include sections where data exists** (omit Media section if no images, omit Thread section if no self-replies, omit Quoted Tweet if none, omit Engagement if no metrics found).

```markdown
---
title: "Tweet by @{handle}"
author: "{display_name}"
handle: "@{handle}"
date: "{YYYY-MM-DD}"
tweet_id: "{tweet_id}"
url: "{canonical_url}"
archived_at: "{current ISO 8601 datetime}"
thread_length: {N}
---

# @{handle} - {display_name}

> {tweet text, each line prefixed with > }

**{human-readable date, e.g. "March 1, 2026 at 3:45 PM"}**

## Media

![Tweet image 1](./images/tweet-{username}-{tweet_id}_1.jpg)
![Tweet image 2](./images/tweet-{username}-{tweet_id}_2.jpg)

## Thread

### 2/{total}

> {reply 1 text}

**{reply 1 date}**

![Reply 1 image](./images/tweet-{username}-{reply1_tweet_id}_1.jpg)

---

### 3/{total}

> {reply 2 text}

**{reply 2 date}**

---

(repeat for each self-reply)

## Quoted Tweet

> **@{quoted_handle}** - {quoted_display_name}
>
> {quoted tweet text}
>
> [{quoted date}]({quoted tweet url})

## Engagement

| Metric | Count |
|--------|-------|
| Replies | {n} |
| Reposts | {n} |
| Likes | {n} |
| Bookmarks | {n} |
| Views | {n} |

---

*Archived from [{canonical_url}]({canonical_url}) on {current date}*
```

Notes on the template:
- **Thread section**: Only include if `threadReplies` from Step 3.6a is non-empty. Number each post as `{index}/{total}` where the main tweet is `1/{total}`. Separate each reply with `---`.
- **`thread_length`** frontmatter: Total number of posts in the thread (main tweet + replies). Omit if not a thread (single tweet).
- If a video is present but cannot be downloaded, add a note in the Media section: `*Video content available at original URL*`
- If this tweet is a reply, add `reply_to: "{parent_tweet_url}"` to the frontmatter
- For failed image downloads, use the remote URL instead of local path
- Engagement counts should use human-readable format if available (e.g., "1.2K" is fine)

## Step 6: Save File

1. Save the Markdown to `mdbird/{username}/tweet-{username}-{tweet_id}.md` using the Write tool
   - The directory `mdbird/{username}/` was already created in Step 4
   - Images are already saved in `mdbird/{username}/images/`
   - Markdown内の画像パスは `./images/tweet-{username}-{tweet_id}_N.jpg` (mdファイルからの相対パス)
2. Report a summary to the user:
   - File path saved
   - Author and handle
   - First ~80 characters of tweet text
   - Thread info: if a thread, report "スレッド: {N}件のポスト" (e.g., "スレッド: 5件のポスト")
   - Number of images saved locally (total across main tweet + thread replies)
   - Any warnings (failed image downloads, video present but not saved, partial thread, etc.)
   - Japanese translation status (if Step 7 was executed)

## Step 7: Japanese Translation (Non-Japanese Content)

After saving the original file, determine the language of the tweet content and create a Japanese translation if needed.

### 7.1 Language Detection

Analyze the tweet text (including article body if present) to determine its primary language:
- If **50% or more** of the characters are Japanese (hiragana, katakana, kanji) → **Skip Step 7 entirely**
- Otherwise → proceed to create a Japanese translation

### 7.2 Generate Translated Markdown

Create a Japanese-translated version of the Markdown file. Use the same structure as the original, with these changes:

- **Frontmatter**: Add `language: "ja"` and `translated_from: "tweet-{username}-{tweet_id}.md"`
- **Tweet text** (blockquote): Translate to natural Japanese (意訳寄り、自然な日本語)
- **Article Content section**: Translate to Japanese
  - Preserve heading hierarchy, bullet structure, and formatting
  - Keep code snippets, file names, URLs, and technical identifiers as-is
  - Translate blockquotes
- **Quoted Tweet**: Translate the text
- **Thread section**: Translate each reply's text to Japanese. Keep image paths, timestamps unchanged.
- **Keep unchanged**:
  - Media section (same relative image paths — images are shared)
  - Engagement section (numbers as-is)
  - Frontmatter basics (author, handle, date, tweet_id, url, thread_length)
  - Section heading for "Engagement" stays as "Engagement"

Translated file template:

```markdown
---
title: "Tweet by @{handle}"
author: "{display_name}"
handle: "@{handle}"
date: "{YYYY-MM-DD}"
tweet_id: "{tweet_id}"
url: "{canonical_url}"
archived_at: "{current ISO 8601 datetime}"
language: "ja"
translated_from: "tweet-{username}-{tweet_id}.md"
---

# @{handle} - {display_name}

> {翻訳されたツイート本文}

**{human-readable date}**

## Media

(same image references as original)

## 記事内容

(translated article body — preserve structure)

## Engagement

(same as original)

---

*[{canonical_url}]({canonical_url}) より {current date} にアーカイブ・翻訳*
```

### 7.3 Save Translated File

Save to `mdbird/{username}/tweet-{username}-{tweet_id}_ja.md` using the Write tool.

### 7.4 Report

Add to the summary report:
- "日本語翻訳版も保存しました: {path}"
- Detected source language (e.g., "原文: 英語")

## Edge Cases

- **Deleted tweet**: If the page shows "このページは存在しません", "This post is from an account that no longer exists", or similar → notify user and stop
- **Protected account**: If "These posts are protected" or "このアカウントのポストは非公開" → notify user and stop
- **Login wall**: Always remove via JS (step 3.2). If content is still not accessible after removal → notify user that login is required and stop
- **Thread tweet**: Archive the specified tweet AND all self-replies (same author) that appear below it on the page. If the specified tweet is a reply to someone else's tweet, note the parent in frontmatter but do NOT include the parent tweet content — only include same-author continuations below the specified tweet.
- **Long threads (10+ replies)**: Scroll multiple times to load all replies. Maximum 5 scroll attempts. If the thread appears truncated, add `partial_thread: true` to frontmatter and note in the summary.
- **Network errors**: If the browser fails to load → notify user and suggest checking network/retrying
- **No images**: Simply omit the Media section
- **No engagement data**: Omit the Engagement section

## Diagnostics

When content extraction is incomplete (partial_content flag set, or tweet text is empty despite the page loading), automatically collect and report the following diagnostic information **before closing the browser**:

1. **DOM element counts** — execute this JavaScript:
   ```javascript
   (()=>{
     return JSON.stringify({
       articles: document.querySelectorAll('article[data-testid="tweet"]').length,
       tweetTexts: document.querySelectorAll('[data-testid="tweetText"]').length,
       images: document.querySelectorAll('img[src*="pbs.twimg.com/media"]').length,
       dialogs: document.querySelectorAll('[role="dialog"]').length,
       layers: document.querySelectorAll('[data-testid="layers"] > div').length
     });
   })()
   ```

2. **Debug screenshot**: Save a screenshot to `mdbird/{username}/debug/debug-{tweet_id}.png`
   - Create the debug directory with `mkdir -p mdbird/{username}/debug`
   - **browser-use**: `MDB screenshot S mdbird/{username}/debug/debug-{tweet_id}.png`
   - **Playwright**: `browser_take_screenshot` (type: png) and save the result

3. **Playwright-only diagnostics** (skip if using browser-use):
   - Console errors: `browser_console_messages` with level: `error`
   - Failed network requests: `browser_network_requests` (includeStatic: false)

Report all diagnostic info to the user alongside the partial content warning.
