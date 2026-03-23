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
  - [browser-use CLI](https://github.com/browser-use/browser-use) (recommended — fast daemon-based automation)
  - Playwright MCP (bundled with the plugin as fallback)

## browser-use CLI セットアップ (推奨)

mdbird は browser-use CLI を優先的に使用します。以下の手順でセットアップしてください:

### 1. CLI のインストール

```bash
# macOS / Linux
curl -fsSL https://browser-use.com/cli/install.sh | bash

# インストール確認
browser-use doctor
```

### 2. Claude Code スキルのインストール (任意)

browser-use の [Claude Code スキル](https://github.com/browser-use/browser-use/blob/main/browser_use/skill_cli/README.md)を導入すると、mdbird 以外のブラウザタスクでも活用できます:

```bash
mkdir -p ~/.claude/skills/browser-use
curl -o ~/.claude/skills/browser-use/SKILL.md \
  https://raw.githubusercontent.com/browser-use/browser-use/main/skills/browser-use/SKILL.md
```

> browser-use CLI がインストールされていない場合、mdbird は同梱の Playwright MCP に自動フォールバックします。

## License

MIT
