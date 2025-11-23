## Submitting GitHub PRs

### Purpose
Ship PRs in a consistent, reviewable, and auditable way—every time.

### Before you start
- New PR work: create a task worktree with `~/.codex/scripts/create_tree.sh <branch> [base]` from repo root (copies env files, installs deps, sets upstream). If you ever create a worktree manually, immediately run `git push -u origin <branch>` (or `git branch --set-upstream-to=origin/<branch> <branch>`) to avoid upstream mismatch.
- Updating/replying on an existing PR: checkout the PR’s branch directly (no new worktree) and ensure it tracks `origin/<branch>`.
- Confirm `gh auth status` works and follow AGENTS.md guardrails for coding standards and security.

### Build & validate
1. Implement the change following repo standards.
2. Run `pnpm format:check`, `pnpm check-all`, and the most relevant `pnpm test` for touched areas.
3. Use Conventional Commits for every commit (e.g., `feat: add invoice aging API (#123)`). Never edit lockfiles manually.

### Prepare the PR
- Include: concise summary, linked issues, UI media (if any), and a `Tests` section with command outputs.
- **MUST** assign reviewers immediately (default: @truewind-ai/truewind-engineering):
  - On create: `gh pr create --reviewer @truewind-ai/truewind-engineering`
  - On update: `gh pr edit --add-reviewer @truewind-ai/truewind-engineering`

### Compose the PR body (avoid literal "\n")
- Write the body in a file so newlines render correctly. Example:
  ```bash
  cat > /tmp/pr.md <<'EOF'
  ## Summary
  - ...

  ## Testing
  - pnpm test foo
  EOF
  gh pr create -F /tmp/pr.md --reviewer @truewind-ai/truewind-engineering
  ```
- Never pass escaped newlines like `"line1\nline2"`; GitHub renders them as `\n` text.

### Verify reviewers (do not skip)
- After creation/update, confirm reviewers are present: `gh pr view --json reviewers --jq '.reviewers[].login'`.
- If empty, immediately run: `gh pr edit --add-reviewer @truewind-ai/truewind-engineering`.
- Log the reviewer check in your task notes (`docs/tasks/...`).

### Request reviews (two touchpoints)
1. Post in Slack `#engineering` (`C05GRNTBUDN`) via `chat.postMessage` with PR link + one-line summary.
2. DM a randomly chosen @eng member (exclude Tennison `U04CDCYD6BS`) asking for review. Grab IDs from `docs/context/slack-channels.md`. Example selector:
   ```bash
   python3 - <<'PY'
   import random
   eng = [
     "U06207X2BK6","U07223EMWJ0","U07HYV833UP","U0868F9RU2Z",
     "U08KE4CRXNV","U08LPE05S15","U09MQ5WS621"
   ]
   print(random.choice(eng))
   PY
   ```
3. Log both pings in your task notes (`docs/tasks/...`).

### After opening
- Monitor CI and address failures quickly.
- Respond to reviewer comments via `gh` following @./instructions/reviewing-or-replying-on-github-prs.md.
- Capture UI snapshots if applicable (see @./instructions/snapshot-requirements-ui-work.md).
