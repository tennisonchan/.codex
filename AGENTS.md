# Agent

## Tooling Defaults
- Use `gh` for every GitHub action (PR creation, replies, metadata updates) so activity stays traceable.
- Use the Linear MCP integration for ticket CRUD/updates instead of ad-hoc notes.
- Capture screenshots with the Playwright MCP; store resulting images under `/docs/screenshots/` (for UI diffs) or `/docs/tasks/` (for workflow evidence) as appropriate.
- Use Bitwarden MCP to retrieve any required passwords or secrets instead of storing them locally.
- Send escalations through Slack's Web API (`chat.postMessage`) with `$SLACK_BOT_TOKEN` per @./instructions/communication-with-slack-api.md so every ping stays auditable.
- Run Codex via `codev` so `.env.local` secrets load automatically (copy `.env.local.example`).
- Store any new Codex helper scripts under `./scripts/`, make them executable, and document their purpose/usage in AGENTS.md when you add them.

## Quick Start Checklist
1. Verify `gh auth status` succeeds; if not, DM Tenn via Slack's Web API (`chat.postMessage` to `tenn=D04BPMQHZJN`) for help.
2. Ensure Slack API env vars (`SLACK_BOT_TOKEN`, `SLACK_CHANNEL_IDS` alias=channel_id) are loaded and include `tenn=D04BPMQHZJN` so decision escalations can be sent immediately.
3. Start Codex through `codev` to load secrets, then follow task-specific instructions below.

## Enrich Knowledge Base & Context
All the context and new knowledge are saved in @./docs/context/
- Slack usage cheat sheet: @./docs/context/slack-channels.md

### Documentation Changes (instructions + context)
If you edit anything under `instructions/`, `docs/context/`, or `AGENTS.md`, commit and push those changes before closing the task (follow @./instructions/submitting-github-prs.md for the workflow).

## Continuous Improvement (after every task)
- Run a short reflection when finishing each task: what slowed you down, what worked well, and what to change next time.
- If the reflection suggests clearer guidance, update AGENTS.md and relevant files in `instructions/` or `docs/context/` immediately (see @./instructions/post-task-reflection.md for the checklist).
- Note in your task log (`docs/tasks/...`) whether you updated instructions or decided no changes were needed.

## Task Instructions
### Add New Instruction
Document reusable lessons after long tasks; see @./instructions/add-new-instruction.md

### Add Context in the Knowledge Base
Record long-task context and insights for future agents; see @./instructions/add-context-in-the-knowledge-base.md

### Post-Task Reflection
Follow the end-of-task reflection loop every time; see @./instructions/post-task-reflection.md

### Task Context & Planning
Keep @./docs/tasks logs updated and maintain multi-step plans for non-trivial work. Details in @./instructions/task-context-and-planning.md

### Slack Communication
Use Slack's Web API (`chat.postMessage`) per @./instructions/communication-with-slack-api.md for both escalations to Tenn (`tenn=D04BPMQHZJN`) and broader engineering comms (`engineering=C05GRNTBUDN`, `escalations-dev=C06TFGKCT1A`).
- Keep messages concise, include the active task reference + ask or decision, verify Slack returns `{"ok": true}`, and note the ping in your task log or next update.

### Snapshot Requirements (UI Work)
Capture Playwright MCP screenshots for any UI-impacting change and save under docs/screenshots. Details in @./instructions/snapshot-requirements-ui-work.md

### Submitting GitHub PRs
Follow the branching, validation, commit, and PR checklist (tests + UI proof). Details in @./instructions/submitting-github-prs.md

### Reviewing or Replying on GitHub PRs
Fetch MEMBER/coding-agent reviews via gh api, address each, and respond before summarizing. Details in @./instructions/reviewing-or-replying-on-gitHub-prs.md
