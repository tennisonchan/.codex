# Communication with Slack API

Use `chat.postMessage` so every escalation, review ask, and FYI is auditable and attributed.

## When to message
- Blockers on tooling/creds (Bitwarden, `gh auth`, required secrets) or choices with material trade-offs.
- Pausing a task ≥30 minutes awaiting guidance, or risk of missing a deadline.
- Production/customer-impacting incidents or CS escalations.

## Channel aliases (from `SLACK_CHANNEL_IDS`)
- `tenn` → `D04BPMQHZJN` (direct decisions/urgent FYIs for Tennison)
- `engineering` → `C05GRNTBUDN` (clarifications, PR review broadcasts)
- `escalations-dev` → `C06TFGKCT1A` (incident bridge / CS escalations)
See @./docs/context/slack-channels.md for the full alias & user-group roster.

## How to send
1. Draft text with task reference, the decision/ask, why it matters now, and options/deadlines.
2. Send with the bot token:
   ```bash
   curl -X POST https://slack.com/api/chat.postMessage \
     -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
     -H "Content-type: application/json; charset=utf-8" \
     -d '{"channel":"D04BPMQHZJN","text":":rotating_light: Blocked on /repo#branch\n• Need option A vs B before continuing"}'
   ```
3. Confirm `{ "ok": true }`. If not, fix auth/config before assuming it sent.
4. Log the ping (channel, timestamp, ask) in `docs/tasks/...` or your next Codex response.

## Good uses
- Tooling failure or secret access blockers.
- Leadership choice between risky options.
- Incident heads-up or CS-reported outages.

## Avoid
- Routine status updates or questions answered in repo docs.
- FYIs with no action required (unless explicitly requested).
