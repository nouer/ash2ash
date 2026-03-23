# mdbird

Archive tweets/X posts as clean Markdown files with locally-saved images.

## Features

- **browser-use CLI 優先**: browser-use CLI が利用可能な場合は優先的に使用（高速なデーモンベースの自動化）
- **Playwright MCP フォールバック**: browser-use が利用できない場合は同梱の Playwright MCP を使用
- 高解像度画像のダウンロード (`name=large`)
- YAML frontmatter 付きの Markdown 生成
- ログインウォールの自動除去、引用ツイート、エンゲージメント指標の取得
- ユーザー名ごとにディレクトリを分けて整理
- **非日本語コンテンツの日本語翻訳版を自動生成** (`_ja.md`)

## Prerequisites

ブラウザツールが1つ以上必要です（優先順に）:

1. **browser-use CLI** (推奨) — `pip install browser-use` でインストール。デーモンベースで高速。
2. **Playwright MCP** (フォールバック) — 本プラグインに同梱されています。追加設定は不要です。

## Usage

```
/mdbird https://x.com/username/status/1234567890
```

`x.com` と `twitter.com` の両方の URL に対応しています。

## Output Structure

```
mdbird/
└── {username}/
    ├── tweet-{username}-{tweet_id}.md          # 原文
    ├── tweet-{username}-{tweet_id}_ja.md       # 日本語翻訳版（非日本語の場合のみ）
    └── images/
        ├── tweet-{username}-{tweet_id}_1.jpg
        └── tweet-{username}-{tweet_id}_2.jpg
```

画像は原文と翻訳版で共有されます（同じ相対パスで参照）。

## Markdown Format

各アーカイブには以下が含まれます:

- YAML frontmatter (author, date, tweet ID, URL, archive timestamp)
- ツイート本文（blockquote 形式）
- ローカル保存された画像（相対パス）
- 引用ツイートの内容（存在する場合）
- エンゲージメント指標テーブル（返信、リポスト、いいね、ブックマーク、表示数）
- 記事型ツイートの全文（Article Content セクション）

### 日本語翻訳版 (`_ja.md`)

ツイートの原文が日本語以外の場合、自動的に日本語翻訳版が生成されます:

- frontmatter に `language: "ja"` と `translated_from` フィールドが追加されます
- 本文・記事内容が自然な日本語に翻訳されます
- コードスニペット、ファイル名、URL はそのまま維持されます
- 画像やエンゲージメント指標は原文と同一です

## Browser Tool Selection

mdbird は以下の優先順でブラウザツールを選択します:

| Priority | Tool | Detection |
|----------|------|-----------|
| 1 | browser-use CLI | `which browser-use` |
| 2 | Playwright MCP (bundled) | `mcp__plugin_mdbird_playwright__` prefix |
| 3 | Playwright MCP (project) | `mcp__playwright__` prefix |
| 4 | Playwright MCP (standalone) | `mcp__plugin_playwright_playwright__` prefix |

## Edge Cases

- **Deleted/suspended tweets**: 検出して報告
- **Protected accounts**: 検出して報告
- **Login walls**: JavaScript インジェクションで自動除去
- **Videos**: サムネイルを取得し、元 URL へのリンクを追加
- **Failed image downloads**: リモート URL にフォールバック
- **Partial content**: 診断情報を収集しデバッグスクリーンショットを保存

## Changelog

### 1.2.0

- browser-use CLI を優先ブラウザツールとして追加（Playwright MCP はフォールバック）
- `wait selector` / `scroll` などの browser-use ネイティブコマンドに対応
- JS スニペットを IIFE 形式に統一し、両ツールで共通利用可能に

### 1.1.0

- 非日本語ツイートの日本語翻訳版（`_ja.md`）を自動保存する機能を追加

### 1.0.0

- 初回リリース
- Playwright MCP によるツイート取得
- 高解像度画像のダウンロード
- YAML frontmatter 付き Markdown 生成
