# Slack Decision Prompts via MCP

The owner wants a Slack ping whenever the agent is blocked waiting for a decision. Use the Slack MCP server so the request is tracked and the conversation link is preserved.

## When to send a Slack ping
- You cannot proceed without a product/infra/design/business decision from Tennison (use the `tenn` channel for these).
- A choice has material trade-offs (budget, downtime, scope) and you need approval.
- You are pausing an in-flight task for more than ~30 minutes to wait for guidance.
## How to send the ping
1. Identify the Slack target from the `SLACK_CHANNEL_IDS` env var (comma-separated IDs):
   - `tenn`(`D04BPMQHZJN`): decisions Tennison must make — default for this playbook.
   - `engineering`(`C05GRNTBUDN`): PR review requests, design clarifications, or technical discussion threads (include PR links when applicable).
   - `escalations-dev`(`C06TFGKCT1A`): when Customer Success reports a bug/incident affecting `truewind-core` and engineering needs context.
2. Draft a short message that includes:
   - The task reference (repo + branch or ticket ID).
   - What decision is needed and why it matters.
   - The clear set of options or questions Tennison must answer.
   - Any deadlines or blockers if timing matters.
3. Call `mcp__slack__slack_post_message` with the channel ID and message text. Keep formatting simple (Slack markdown is supported).
4. Note in your task log (or next Codex reply) that a Slack notification was sent so future agents see the escalation.

## Example tool call
```
{
  "channel_id": "C0123456789",
  "text": ":rotating_light: Decision needed on /truewind-core#feature/api-batching\n• Context: retry logic is tangled with legacy queueing\n• Need: pick between fast bandaid vs. two-day rewrite\nPlease reply with 1) Bandaid, 2) Rewrite, or 3) Other idea."
}
```

### Example: Missing prerequisites
If `gh auth status` fails or the Bitwarden MCP env vars are absent, stop work and escalate:
```
{
  "channel_id": "tenn",
  "text": ":warning: Blocked on tooling setup for /Users/tennisonchan/.codex\n• gh auth status fails (no stored token) / Bitwarden env vars missing\n• Need Tenn to confirm creds or share updated secrets before we can proceed."
}
```

## Dry run
- Scenario: While implementing invoice syncing you discover two mutually-exclusive data models and need Tennison to choose one before migrating production data.
- Action: Compose the Slack text summarizing both models, note risk/time for each, and explicitly ask which path to take.
- Tool: `mcp__slack__slack_post_message` → `channel_id=<primary channel>`, `text="Need decision: Invoice sync schema (Option A keeps legacy tables, Option B rebuilds on new view). A = 0 downtime but manual clean-up later; B = 1hr maintenance window now. Which path do you prefer?"`
- Result: Tennison gets pinged immediately, can reply in Slack, and you document in the task log that you're waiting on that decision.
