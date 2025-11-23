# Linear Worktrees

When to use: every time you start or resume work on a Linear ticket.

Naming: worktree == branch == `<linear-key>-<slug>` (example: `ABC-1234-fix-payments`). Reuse the same slug across updates for that ticket.

Steps:
1. Find existing worktree: `git worktree list | rg '<linear-key>'`.
2. If found and **not** merged into `origin/main` (`git branch --contains origin/main | rg '<linear-key>'` is empty), `cd` into that worktree and continue.
3. Otherwise create a new one: `~/.codex/scripts/create_tree.sh <linear-key>-<slug> [origin/main]`.

Audit: record the chosen worktree path and branch in `docs/tasks/YYYY-MM-DD-<slug>.md` under Context/Setup before editing.

Safeguard: if multiple worktrees match the same Linear key, stop and ping Tenn before proceeding.

Optional helper: `wticket() { key=$1; slug=$2; name="${key}-${slug}"; git worktree list | rg "$key" || ~/.codex/scripts/create_tree.sh "$name"; cd "$(git worktree list | awk -v n="$name" '$0 ~ n {print $1; exit}')"; }`
