# Add Context in Knowledge Base

Some solutions capture tribal knowledge that only surfaces during long or complex tasks. When that happens:

1. Evaluate whether the insight will help future agents avoid pitfalls or ramp up faster.
2. If yes, describe the scenario, decisions, and outcomes in a dedicated markdown file within `./docs/context/` (this file lives there as an example).
3. Capture concise, action-oriented takeaways so others can skim quickly.
4. When the new document is ready, add a short summary plus an `@./docs/context/...` reference inside `instructions.md` so every agent sees it under Task Instructions.

Keeping contextual write-ups in `./docs/context` makes it easy to link supporting evidence, screenshots, or timelines alongside process guidance stored under `./instructions`.
