# mdbird

Archive tweets/X posts as clean Markdown files with locally-saved images.

## Features

- **browser-use CLI 優先**: browser-use 1.0 以降が利用可能な場合は優先的に使用。専用の headless Chrome で動き、利用中の Chrome には触れない
- **Playwright MCP フォールバック**: browser-use が利用できない場合は同梱の Playwright MCP を使用
- 高解像度画像のダウンロード (`name=large`)
- YAML frontmatter 付きの Markdown 生成
- ログインウォールの自動除去、引用ツイート、エンゲージメント指標の取得
- ユーザー名ごとにディレクトリを分けて整理
- **非日本語コンテンツの日本語翻訳版を自動生成** (`_ja.md`)

## Prerequisites

ブラウザツールが1つ以上必要です（優先順に）:

1. **browser-use CLI 1.0 以降** (推奨) — デーモンベースで高速。セットアップは下記参照。
2. **Playwright MCP** (フォールバック) — 本プラグインに同梱されています。追加設定は不要です。

### browser-use CLI のセットアップ

**browser-use 1.0 以降が必要です。** 1.0 で CLI の書き方が変わり、0.x とは互換がありません。

#### 1. CLI のインストール

```bash
uv tool install browser-use        # 更新は uv tool upgrade browser-use
# または: pip install -U browser-use
```

インストール後の確認:
```bash
browser-use --version   # "browser-use 1.x (browser-harness ...)" と出れば 1.0 以降
browser-use --doctor    # インストールを検証
```

mdbird は Chrome / Chromium も使います（`google-chrome`・`chromium`・macOS の Google Chrome.app を自動で探します。別の場所なら `MDBIRD_CHROME` で指定）。

#### 2. Claude Code スキルのインストール（任意）

browser-use の Claude Code スキルを導入すると、mdbird 以外のブラウザ操作タスクでも browser-use が活用されます:

```bash
browser-use skill install
```

> **Note:** スキルのインストールは任意です。mdbird は同梱の `scripts/mdb-browser.sh` から browser-use を呼ぶので、スキルなしでも動作します。

#### 利用中の Chrome には触れません

browser-use 1.0 は、既定では**いま動いている Chrome**につなぎます。mdbird はこれを使わず、取得のたびに専用の headless Chrome を使い捨てのプロファイルで立て、そこだけを操作します。終わったら止めてプロファイルも消します（止め忘れても30分で自動停止）。

#### ログイン用クッキー（任意）

`~/.config/mdbird/x_cookies.json`（または `x-cookies.json`、環境変数 `MDBIRD_COOKIES`）があれば読み込みます。クッキーの配列か `{"auth_token": "...", "ct0": "..."}` の形に対応しています。スレッドの返信や長文記事の全文の取得に効きます。**パスワード級の秘密なので、リポジトリに入れず権限 600 で置いてください。**

詳細: [browser-use](https://github.com/browser-use/browser-use)

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
| 1 | browser-use CLI (1.0+) | `scripts/mdb-browser.sh check` |
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

### 1.3.1

- X が自動で翻訳して表示した投稿を、取得の前に「原文を表示」で原文へ戻す。スレッドの返信も対象にした

### 1.3.0

- browser-use 1.0 に対応。廃止されたサブコマンド（`open`・`eval`・`scroll`・`screenshot`・`close`）の代わりに、同梱の `scripts/mdb-browser.sh` から操作する
- 専用の headless Chrome を使い捨てのプロファイルで立てて操作し、利用中の Chrome には触れない。止め忘れても30分で自動停止
- タブを表に出して、遅延読み込みの画像を取りこぼさないようにした
- ログイン用クッキーを CDP で入れる（`x_cookies.json`／`x-cookies.json`／`MDBIRD_COOKIES`）
- 同じ作者のスレッドの返信を取得する

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
