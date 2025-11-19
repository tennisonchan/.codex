# Slack Channel Roles

Always follow @./instructions/communication-with-slack-api.md: send escalations via Slack's Web API (`chat.postMessage`) with `$SLACK_BOT_TOKEN`, selecting the channel alias from `SLACK_CHANNEL_IDS`.

- `tenn` (`D04BPMQHZJN`): Private DM to Tennison for blocker escalations, decision prompts, or urgent FYIs that must reach Tenn directly. Include the active task ID/branch, describe the decision or assistance needed, and log the ping in docs/tasks or your Codex update.
- `engineering` (`C05GRNTBUDN`): Team-wide engineering room for PR review requests (attach the PR link), architectural clarifications, or heads-up broadly relevant to builders.
- `escalations-dev` (`C06TFGKCT1A`): Customer Success / incident bridge for production-impacting bugs; loop in when CS reports an outage or financial discrepancy that engineers must triage immediately.

Keep these IDs synced with `SLACK_CHANNEL_IDS` (format `alias=channel_id`) so your automation payloads resolve to the right targets.
