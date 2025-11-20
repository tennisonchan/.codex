## Reviewing or Replying on GitHub PRs

### Get the feedback
- Identify the PR URL.
- Inline comments: `gh api repos/<org>/<repo>/pulls/<PR_NUMBER>/comments --paginate` and keep only `author_association == "MEMBER"` or coding-agent accounts (often `-agent` or `author_association == "NONE"`).
- Review summaries: `gh api repos/<org>/<repo>/pulls/<PR_NUMBER>/reviews --paginate` for high-level feedback.

### Process each comment
- Decide: code change, clarification, or both. Make the change before replying when possible.
- If you change code, create a Conventional Commit and push it (`git commit -am "fix: <scope> <short detail>" && git push`); do this **before** you post the reply.
- Reply via API: `gh api repos/<org>/<repo>/pulls/comments/<COMMENT_ID>/replies --method POST -f body='<message>'` (no placeholder replies).
- When changes were made, cite the file/section and tests run. For acknowledgements, keep concise but still send via the API.

### Finish
- Ensure every MEMBER/coding-agent comment has a response.
- Confirm the branch is pushed (no unpushed commits) and the replies are visible on GitHub.
- Mention in your final PR update that all such comments were addressed.
