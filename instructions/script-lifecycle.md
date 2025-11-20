# Script Lifecycle

Use this when creating or updating helper scripts so they stay discoverable and safe.

1) Scope: keep scripts small, single-responsibility, and named `verb-target.sh`.
2) Location: place scripts in `./scripts/`; make them executable (`chmod +x`).
3) Header: include shebang, short description, inputs/flags, usage example, and external deps.
4) Logging: echo actionable errors; fail fast with `set -euo pipefail`.
5) Docs: add a one-liner to `scripts/README.md` and list it in AGENTS.md Scripts.
6) Validation: run the script once (or dry-run) and note the command in your task log.
7) Shipping: commit the script alongside related code/docs; mention it in PR notes/Slack updates.
