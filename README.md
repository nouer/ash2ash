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

## License

MIT
