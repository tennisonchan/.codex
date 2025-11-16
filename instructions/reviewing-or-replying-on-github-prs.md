## Reviewing or Replying on GitHub PRs
- Identify the PR URL; ask if unclear.
- Fetch inline comments via `gh api repos/<org>/<repo>/pulls/<PR_NUMBER>/comments --paginate | jq ...` and keep only entries where `author_association` is `"MEMBER"` or from coding-agent accounts (often ending with `-agent` or `author_association == "NONE"`).
- Fetch review summaries with `gh api repos/<org>/<repo>/pulls/<PR_NUMBER>/reviews --paginate` to capture high-level feedback.
- For each MEMBER or coding-agent comment: decide whether it needs a code change, a clarification, or both. Make necessary code edits before responding.
- Reply via `gh api repos/<org>/<repo>/pulls/comments/<COMMENT_ID>/replies --method POST -f body='<message>'`; avoid placeholder or throwaway replies.
- Reference the affected file/section and tests in your reply when changes were made. For acknowledgements, keep responses concise but still routed through the API.
- After all qualifying comments are addressed, note in your final update that every MEMBER and coding-agent comment on the PR received a response.
