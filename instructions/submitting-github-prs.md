## Submitting GitHub PRs
1. Branching: start from a clean `main` (via `git worktree`) before making changes.
2. Implementation: follow repo guardrails in `AGENTS.md` (coding standards, toolchain, security, etc.).
3. Validation: run `pnpm format:check`, `pnpm check-all`, and the most relevant targeted `pnpm test` for the code you touched.
4. Commit: use Conventional Commit syntax (e.g., `feat: add invoice aging API (#123)`) and never edit lockfiles manually.
5. UI proof: if UI changed, attach the Playwright snapshots noted above, refer to @./instructions/snapshot-requirements-ui-work.md
6. PR: push the branch, open the PR with a clear description, linked issues, UI media, and a “Tests” section. Assign reviewer `truewind-engineering`.
