# Slack Channel & User Group Reference

Use @./instructions/communication-with-slack-api.md with `chat.postMessage` and aliases from `SLACK_CHANNEL_IDS`.

## Channel aliases
- `tenn` (`D04BPMQHZJN`): DM Tennison for blockers, decision prompts, or urgent FYIs. Include task ID/branch and log the ping in `docs/tasks/...`.
- `engineering` (`C05GRNTBUDN`): PR review requests (attach link + one-line summary), architectural clarifications, broad engineering heads-ups.
- `escalations-dev` (`C06TFGKCT1A`): Incident bridge when CS reports outages/financial discrepancies; use for production-impacting bugs.

Keep these IDs synced with `SLACK_CHANNEL_IDS` (`alias=channel_id`) so automation payloads resolve correctly.

## User groups
- `@eng` (`S04DBQR22LE`):
  - `U04CDCYD6BS` Tennison Chan
  - `U06207X2BK6` Caio Carvalho
  - `U07223EMWJ0` Renato Menegasso
  - `U07HYV833UP` Greg Konush
  - `U0868F9RU2Z` Tiago Romero
  - `U08KE4CRXNV` Chev Eldrid
  - `U08LPE05S15` Jeff Lai
  - `U09MQ5WS621` Vijayasankar Jothi

Use this roster when randomly selecting an @eng reviewer DM (exclude Tennison by default).
