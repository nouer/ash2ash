# ash2ash

Web content archival plugins for [Claude Code](https://claude.com/claude-code).

## Plugins

| Plugin | Description |
|--------|-------------|
| [mdbird](./plugins/mdbird/) | Archive tweets/X posts as clean Markdown files with locally-saved images |

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
- [Playwright plugin](https://github.com/anthropics/claude-code-plugins) (required by mdbird)

## License

MIT
