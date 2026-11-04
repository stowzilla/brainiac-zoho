# brainiac-zoho

Zoho Mail webhook plugin for [Brainiac](https://github.com/stowzilla/brainiac) — the multi-agent orchestration layer.

## What It Does

- **Email Notifications** — rule-based matching of incoming emails, notifications via any notify channel (Discord by default)
- **Email Triage** — rules with `dispatch_agent` send the email to an AI agent that decides if it needs a card
- **OAuth Flow** — browser-based Zoho OAuth for API access (content fetching)
- **Fallback Rules** — catches unmatched emails so nothing slips through

## Installation

```bash
brainiac install zoho
brainiac restart
```

Install creates a starter `~/.brainiac/zoho.json`; `brainiac zoho setup` creates
one from `templates/zoho.json.example` if it's missing.

## Configuration

Config lives at `~/.brainiac/zoho.json` (under `$BRAINIAC_DIR` if set). Changes
are picked up on the next webhook — no restart needed:

```json
{
  "hook_secret": null,
  "default_notify_target": "YOUR_CHANNEL_ID",
  "notify_channel": "discord",
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

### Rules

The first enabled rule whose non-empty filters all match wins; otherwise `fallback`
applies (if enabled). Rule keys:

| Key | Meaning |
|-----|---------|
| `from_contains`, `to_contains`, `subject_contains`, `body_contains` | Case-insensitive substring filters (empty = ignored) |
| `exclude_words` | Skip the rule if any word appears anywhere in the email (also on `fallback`) |
| `label`, `emoji`, `show_body` | Notification formatting (`show_body` fetches full content via the API) |
| `notify_target`, `notify_channel`, `notify_as` | Per-rule overrides of the top-level defaults |
| `dispatch_agent` | Instead of notifying, dispatch this agent to triage the email |

### Email Triage (Optional)

Rules with `dispatch_agent` need these top-level keys for card creation:

```json
{
  "triage_board_id": "YOUR_BOARD_ID",
  "triage_project_tags": [{ "tag": "stowzilla", "description": "Stowzilla app emails" }],
  "triage_agent_assignment": ["Billing questions → Galen"]
}
```

The agent's decision is emitted as `:create_work_item` (handled by a card plugin
such as brainiac-fizzy), tagged `support`.

### Agents

New agents are created with `brainiac agent create` in Brainiac core. This plugin
has no `on_agent_created` step — just reference the agent by name in
`notify_as` or `dispatch_agent`.

### Zoho Webhook Setup

1. Go to Zoho Mail → Settings → Developer Space → Outgoing Webhooks
2. Add webhook URL: `https://your-ngrok.ngrok-free.app/zoho`
3. On first trigger, Zoho sends the signing secret automatically

### Zoho Mail API (Optional)

For fetching full email content (webhook payloads only include summaries):

1. Create a server-based client in the [Zoho API Console](https://api-console.zoho.com/)
   with redirect URI `http://localhost:4567/zoho/callback`
2. Add an `api` section to `zoho.json` with `client_id` and `client_secret`
3. Visit `http://localhost:4567/zoho/auth` to complete OAuth
4. The `refresh_token` and `account_id` are saved automatically

## CLI

```bash
brainiac zoho setup     # Create config file from template (if missing)
brainiac zoho config    # Show current configuration
brainiac zoho auth      # Print OAuth setup instructions
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
