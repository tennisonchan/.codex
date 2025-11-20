## Submitting GitHub PRs
1. Branching: create a fresh worktree per task using `~/.codex/scripts/create_tree.sh <branch> [base-branch]` from the repo root so env files copy, deps install, and upstream is set to `origin/<branch>`; if you create a worktree manually, immediately run `git push -u origin <branch>` (or `git branch --set-upstream-to=origin/<branch> <branch>`) to avoid upstream/default push mismatch.
2. Implementation: follow repo guardrails in `AGENTS.md` (coding standards, toolchain, security, etc.).
3. Validation: run `pnpm format:check`, `pnpm check-all`, and the most relevant targeted `pnpm test` for the code you touched.
4. Commit: use Conventional Commit syntax (e.g., `feat: add invoice aging API (#123)`) and never edit lockfiles manually.
5. UI proof: if UI changed, attach the Playwright snapshots noted above, refer to @./instructions/snapshot-requirements-ui-work.md
6. PR: push the branch, open the PR with a clear description, linked issues, UI media, and a “Tests” section. Always tag the GitHub team reviewer `truewind-engineering` (on create: `gh pr create --reviewer truewind-engineering`; if updating an open PR: `gh pr edit --add-reviewer truewind-engineering`).
7. Ask for review: post the PR link and a one-line summary in the `engineering` Slack channel via `chat.postMessage`, then DM a randomly chosen @eng member (exclude Tennison `U04CDCYD6BS`) asking for a review. Use the roster in `docs/context/slack-channels.md` to pick the DM target (e.g., `python3 - <<'PY'` with the ID list and `random.choice`), and log both pings in your task notes.
