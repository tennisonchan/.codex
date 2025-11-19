# Communication with Slack API

Use Slack's Web API directly to escalate urgent blockers or request key decisions from Tennison. Follow Slack's `chat.postMessage` method (see https://docs.slack.dev/reference/methods/chat.postMessage/) so every ping is auditable and properly attributed.

## When to send a Slack message
- You're blocked because a tool, secret, or prerequisite (e.g., Bitwarden, `gh auth`) is broken and requires Tennison's attention.
- You need Tennison to choose between options with material trade-offs (budget, downtime, scope, security).
- You're pausing an in-flight task for ~30 minutes or more awaiting guidance, or you risk missing a deadline without input.
- A customer-facing incident or data issue surfaced and Tennison must be aware immediately.

## How to send the message via Slack API
1. **Pick the right channel** using `SLACK_CHANNEL_IDS` (comma-separated `alias=channel_id`). Defaults:
   - `tenn` (`D04BPMQHZJN`): direct decisions or urgent FYIs for Tennison.
   - `engineering` (`C05GRNTBUDN`): design clarifications or request-for-review broadcasts.
   - `escalations-dev` (`C06TFGKCT1A`): production/runtime incidents.
2. **Draft the payload** with:
   - Task reference (`repo#branch`, ticket ID, or doc path).
   - What decision/attention is needed and why it matters right now.
   - Options or explicit questions plus any deadlines.
3. **Call Slack's `chat.postMessage`** using the bot token (`$SLACK_BOT_TOKEN`). Example cURL:
   ```bash
   curl -X POST https://slack.com/api/chat.postMessage \
     -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
     -H "Content-type: application/json; charset=utf-8" \
     -d '{
       "channel": "D04BPMQHZJN",
       "text": ":rotating_light: Blocked on /truewind-core#invoice-sync\n• Need Tennison to pick Option A vs B before continuing"
     }'
   ```
   Refer to Slack's method reference for optional fields like `thread_ts`, `blocks`, or attachments.
4. **Document the escalation** in your task log (under `docs/tasks/…`) or your next Codex response noting exactly when and why you pinged Slack.

## Good examples
- *Tooling failure:* "`gh auth status` keeps failing with 401 even after refreshing tokens; need Tennison to confirm credentials." → Send to `tenn`.
- *High-impact decision:* "Choosing between 1-hour maintenance window now vs. risky hotfix later; Tennison must choose." → Summarize both options and ask for explicit selection.
- *Incident heads-up:* "Customer reported ledger mismatch affecting invoices >$50k; engineering needs Tennison's visibility." → Send to `escalations-dev` and include incident link.

## Bad fits (don't ping Slack)
- Routine status updates that can wait for the daily summary.
- Questions you can answer by checking repo docs or existing tickets.
- FYIs that don't require action, unless specifically requested by Tennison.

Always verify the API response: a JSON `{ "ok": true, ... }` means Slack accepted the message. If you receive `invalid_auth` or any `ok: false` response, fix the token/config immediately before concluding the escalation is sent.
