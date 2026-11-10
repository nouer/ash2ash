# ash2ash

Web content archival plugins for [Claude Code](https://claude.com/claude-code).

## Plugins

| Plugin | Version | Description |
|--------|---------|-------------|
| [mdbird](./plugins/mdbird/) | 1.2.0 | Archive tweets/X posts as clean Markdown files with locally-saved images |

## Installation

Add this marketplace in Claude Code:

```bash
claude plugin install mdbird@nouer/ash2ash
```

Or add the marketplace manually to `~/.claude/settings.json`:

```json
{
  "plugins": {
    "marketplaces": [
      "nouer/ash2ash"
    ]
  }
}
```

## Requirements

- [Claude Code](https://claude.com/claude-code)
- **Browser tool** (one of the following):
  - [browser-use CLI](https://github.com/browser-use/browser-use) 1.0+ (recommended — fast daemon-based automation)
  - Playwright MCP (bundled with the plugin as fallback)

## browser-use CLI セットアップ (推奨)

mdbird は browser-use CLI（**1.0 以降**）を優先的に使用します。1.0 で CLI の書き方が変わり、0.x とは互換がありません。

### 1. CLI のインストール

```bash
uv tool install browser-use        # 更新は uv tool upgrade browser-use
# または: pip install -U browser-use

# インストール確認
browser-use --version
browser-use --doctor
```

Chrome / Chromium も必要です。mdbird は取得のたびに専用の headless Chrome を立てて使い、利用中の Chrome には触れません。

### 2. Claude Code スキルのインストール (任意)

```bash
browser-use skill install
```

> browser-use CLI（1.0 以降）が使えない場合、mdbird は同梱の Playwright MCP に自動フォールバックします。

## License

MIT
