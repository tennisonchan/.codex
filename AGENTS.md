# Agent

## Tooling Defaults
- Use `gh` for every GitHub action (PR creation, replies, metadata updates) so activity stays traceable.
- Create a fresh branch for each task with `git worktree`; keep the main worktree clean.
- Use the Linear MCP integration for ticket CRUD/updates instead of ad-hoc notes.
- Capture screenshots with the Playwright MCP; store resulting images under `/docs/screenshots/` (for UI diffs) or `/docs/tasks/` (for workflow evidence) as appropriate.
- Use Bitwarden MCP to retrieve the password
- Run Codex via `codev` so `.env.local` secrets load automatically (copy `.env.local.example`).

## Quick Start Checklist
1. Verify `gh auth status` succeeds; if not, ping Tenn via the Slack MCP (`tenn` channel) for help.
2. Ensure Slack MCP env (`SLACK_CHANNEL_IDS`, etc.) includes the `tenn` channel so decision escalations can be sent immediately.
3. Start Codex through `codev` to load secrets, then follow task-specific instructions below.

## Knowledge Base & Context
All the context and new knowledge are saved in @./docs/context/
- Slack usage cheat sheet: @./docs/context/slack-channels.md

### Documentation Changes (instructions + context)
If you edit anything under `instructions/` or `docs/context/`, you must commit those changes and push them to GitHub before closing the task (follow @./instructions/submitting-gitHub-prs.md for the workflow).

## Task Instructions
### Add New Instruction
Document reusable lessons after long tasks; see @./instructions/add-new-instruction.md

### Add Context in the Knowledge Base
Record long-task context and insights for future agents; see @./instructions/add-context-in-the-knowledge-base.md

### Task Context & Planning
Keep @./docs/tasks logs updated and maintain multi-step plans for non-trivial work. Details in @./instructions/task-context-and-planning.md

### Snapshot Requirements (UI Work)
Capture Playwright MCP screenshots for any UI-impacting change and save under docs/screenshots. Details in @./instructions/snapshot-requirements-ui-work.md

### Submitting GitHub PRs
Follow the branching, validation, commit, and PR checklist (tests + UI proof). Details in @./instructions/submitting-gitHub-prs.md

### Reviewing or Replying on GitHub PRs
Fetch MEMBER/coding-agent reviews via gh api, address each, and respond before summarizing. Details in @./instructions/reviewing-or-replying-on-gitHub-prs.md

### Decision Prompts via Slack MCP
Before pausing for a user decision, ping Tennison through the Slack MCP (default channel: `tenn`) so the choice is captured out-of-band. Details in @./instructions/slack-decision-prompts.md
