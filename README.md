# brainiac-zoho

Zoho Mail webhook plugin for [Brainiac](https://github.com/stowzilla/brainiac) — the multi-agent orchestration layer.

## What It Does

- **Email Notifications** — rule-based matching of incoming emails, notifications to Discord
- **Email Triage** — AI agent dispatched to decide if support emails need a card
- **OAuth Flow** — browser-based Zoho OAuth for API access (content fetching)
- **Fallback Rules** — catches unmatched emails so nothing slips through

## Installation

```bash
brainiac install zoho
brainiac restart
```

## Configuration

Config lives at `~/.brainiac/zoho.json`:

```json
{
  "hook_secret": null,
  "default_discord_channel_id": "YOUR_CHANNEL_ID",
  "notify_as": "merlin",
  "rules": [
    {
      "label": "Item Sold",
      "enabled": true,
      "subject_contains": "sold",
      "emoji": "💰"
    }
  ],
  "fallback": {
    "enabled": true,
    "label": "Unmatched Email",
    "emoji": "📬"
  }
}
```

The `hook_secret` is auto-captured from Zoho's initial handshake — no manual configuration needed.

### Zoho Webhook Setup

1. Go to Zoho Mail → Settings → Developer Space → Outgoing Webhooks
2. Add webhook URL: `https://your-ngrok.ngrok-free.app/zoho`
3. On first trigger, Zoho sends the signing secret automatically

### Zoho Mail API (Optional)

For fetching full email content (webhook payloads only include summaries):

1. Add `api` section to `zoho.json` with `client_id` and `client_secret`
2. Visit `http://localhost:4567/zoho/auth` to complete OAuth
3. The `refresh_token` and `account_id` are saved automatically

## CLI

```bash
brainiac zoho setup     # Create config file from template
brainiac zoho config    # Show current configuration
brainiac zoho auth      # Instructions for OAuth setup
```

## Hooks Emitted

| Hook | When | Payload |
|------|------|---------|
| `:create_work_item` | Triage agent decides to create card | board_id, title, description, tags, assign_to |

## Development

```bash
git clone https://github.com/stowzilla/brainiac-zoho.git
cd brainiac-zoho
bundle install
bundle exec rake test
bundle exec rubocop
```

## License

MIT
