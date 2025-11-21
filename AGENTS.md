# Agent Handbook

## Core Behaviors
- **Implementation**: Work from a dedicated task worktree and keep an audit trail for every action (Slack pings via API, PR actions via `gh`, task notes in `~/.codex/docs/tasks`).
- Default to accuracy and traceability: cite sources, log decisions.
- MUST: Improve the instructions and grow the knowledge base every task: convert new learnings into `docs/context/`, `instructions/`, or `scripts/` and surface them in this handbook.
- MUST: Follow the linked SOPs instead of improvising; update them immediately when you find gaps.

## Quick Start (always)
1. Run `gh auth status`; if broken, ping Tenn (`tenn=D04BPMQHZJN`) via Slack API.
2. Start Codex through `codev` so `.env.local` is loaded; confirm `SLACK_BOT_TOKEN` and `SLACK_CHANNEL_IDS` (must include `tenn=D04BPMQHZJN`).
3. For new work: create a task worktree using `~/.codex/scripts/create_tree.sh <branch> [base]` before editing. When updating/replying to an existing PR, **do not create a new worktree**—checkout the PR branch and work directly on it (ensure upstream is set if missing).
4. Open or create `docs/tasks/{timestamp}-{slug}.md` for this task; capture goal and initial plan.

## Tooling Defaults
- GitHub: use `gh` for PRs, reviews, metadata; keep all GitHub actions traceable.
- Linear: use the Linear MCP for ticket CRUD/updates instead of ad-hoc notes.
- Slack: send all pings through `chat.postMessage` (see @./instructions/communication-with-slack-api.md).
- Secrets: pull credentials via Bitwarden MCP only.
- UI proof: capture Playwright MCP screenshots; store under `docs/screenshots/` (UI diffs) or `docs/tasks/` (workflow evidence).
- Scripts: store new helper scripts under `./scripts/`, make them executable, and document them here when added.

## Operating Loop (Living Knowledge)
1. **Log & Plan** — Use `docs/tasks/{timestamp}-{slug}.md`; follow @./instructions/task-context-and-planning.md.
2. **Communicate** — Use Slack API for escalations/updates; channel aliases: @./docs/context/slack-channels.md; SOP: @./instructions/communication-with-slack-api.md.
3. **Build** — Write a ticket-derived acceptance checklist before coding (see @./instructions/implementation-accuracy-sop.md); follow repo guardrails; for UI work take snapshots per @./instructions/snapshot-requirements-ui-work.md.
4. **Ship** — Branch/validation/PR text/review requests per @./instructions/submitting-github-prs.md.
5. **Capture & Grow (do every task)** — Decide which artifacts to add:
   - Task log: keep `docs/tasks/{timestamp}-{slug}.md` up to date.
   - Context: add `docs/context/{slug}.md` (scenario → decision → outcome). Link it in AGENTS under Context Hotlinks.
   - Instruction: add `instructions/{topic}.md` (purpose, when to use, steps, examples). Link it in AGENTS under SOPs.
   - Script: add to `scripts/` with exec bit, shebang, and header (what it does, inputs, usage). Update `scripts/README.md` and list it in AGENTS Scripts.
6. **Reflect & Publish** — Run @./instructions/post-task-reflection.md. Commit/push code + new artifacts together; note new docs/scripts in PR/Slack updates.

## Artifact Rules
- `docs/tasks/` — one file per task, `YYYY-MM-DD-slug.md`; summarize goal, plan, decisions, blockers, links (PRs, tickets, screenshots).
- `docs/context/` — reusable knowledge; start with a 3–5 bullet takeaway; include timelines/evidence links if useful.
- `instructions/` — repeatable process guides; keep single-focus; include "When to use" and "Steps"; prefer command snippets over prose.
- `scripts/` — name `verb-target.sh`; include header with description/usage/deps; mark executable; keep examples minimal and tested.
- `docs/screenshots/` — UI proof: store Playwright MCP captures; link from task/context docs.

## Indexes to Maintain
- **SOPs**: @./instructions/task-context-and-planning.md, @./instructions/communication-with-slack-api.md, @./instructions/snapshot-requirements-ui-work.md, @./instructions/submitting-github-prs.md, @./instructions/reviewing-or-replying-on-github-prs.md, @./instructions/post-task-reflection.md, @./instructions/add-new-instruction.md, @./instructions/add-context-in-the-knowledge-base.md, @./instructions/script-lifecycle.md, @./instructions/implementation-accuracy-sop.md.
- **Context Hotlinks**: start at @./docs/context/slack-channels.md; add new context docs as they are created.
- **Scripts**: @./scripts/create_tree.sh (task worktree bootstrap). Add each new script here and in `scripts/README.md` with a one-liner.

## Knowledge Base
- Context and reference docs live in `./docs/context/`.
- When `instructions/`, `docs/context/`, `scripts/`, or this file change, commit and push them with the task’s code (see @./instructions/submitting-github-prs.md).
