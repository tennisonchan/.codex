# Agent Handbook

## Core Behaviors
- Work from a dedicated task worktree and keep an audit trail for every action (Slack pings via API, PR actions via `gh`, task notes in `docs/tasks`).
- Default to accuracy and traceability: cite sources, log decisions, and keep secrets in Bitwarden MCP only.
- Follow the linked SOPs instead of improvising; update them immediately when you find gaps.

## Quick Start (always)
1. Run `gh auth status`; if broken, ping Tenn (`tenn=D04BPMQHZJN`) via Slack API.
2. Start Codex through `codev` so `.env.local` is loaded; confirm `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_IDS` (must include `tenn=D04BPMQHZJN`).
3. Create a task worktree using `~/.codex/scripts/create_tree.sh <branch> [base]` before editing; if you ever work manually, set upstream immediately (`git push -u origin <branch>`).

## Tooling Defaults
- GitHub: use `gh` for PRs, reviews, metadata; keep all GitHub actions traceable.
- Linear: use the Linear MCP for ticket CRUD/updates instead of ad-hoc notes.
- Slack: send all pings through `chat.postMessage` (see @./instructions/communication-with-slack-api.md).
- Secrets: pull credentials via Bitwarden MCP only.
- UI proof: capture Playwright MCP screenshots; store under `docs/screenshots/` (UI diffs) or `docs/tasks/` (workflow evidence).
- Scripts: store new helper scripts under `./scripts/`, make them executable, and document them here when added.

## Standard Task Flow
1. **Log & Plan** — Open/create `docs/tasks/{timestamp}-{slug}.md`, capture goal/assumptions, and make a multi-step plan (see @./instructions/task-context-and-planning.md).
2. **Communicate** — Use Slack API for escalations and updates; channel aliases live in @./docs/context/slack-channels.md and the SOP is @./instructions/communication-with-slack-api.md.
3. **Build** — Follow repo guardrails; for UI work take snapshots (see @./instructions/snapshot-requirements-ui-work.md).
4. **Ship** — Use @./instructions/submitting-github-prs.md for branching, validation, PR text, and review requests (channel post + random @eng DM).
5. **Review loops** — When responding on PRs, follow @./instructions/reviewing-or-replying-on-github-prs.md.
6. **Reflect & Capture** — Run the loop in @./instructions/post-task-reflection.md; add new instructions/context per @./instructions/add-new-instruction.md and @./instructions/add-context-in-the-knowledge-base.md.

## Knowledge Base
- Context and reference docs live in `./docs/context/` (start with @./docs/context/slack-channels.md).
- When `instructions/`, `docs/context/`, or this file change, commit and push them before closing the task (workflow in @./instructions/submitting-github-prs.md).
