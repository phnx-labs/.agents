# Posting a PR review

Use the reviewed head SHA, not a newer revision the reviewer has not seen. Recheck the
head before posting; if it changed, reassess the affected diff. Anchor findings only to
valid right-side diff lines. Findings outside the hunks belong in the review body.

One GitHub review request can carry both the verdict and inline comments:

```json
{
  "body": "CHANGES REQUESTED — concise evidence and findings outside the diff",
  "event": "COMMENT",
  "commit_id": "<reviewed-head-sha>",
  "comments": [
    {"path": "src/example.ts", "line": 42, "side": "RIGHT", "body": "Concrete defect, evidence, and consequence"}
  ]
}
```

Write the payload to a file inside the worktree's `.agents/scratch/` and use:

```bash
gh api repos/<owner>/<repo>/pulls/<number>/reviews --input <payload-file>
```

Omit `comments` when there are no inline findings. Use `COMMENT` by default;
`formal-review` allows `REQUEST_CHANGES` when appropriate. Never self-approve.
If an inline anchor is rejected, preserve the findings in a body comment with
`gh pr comment <number> --body-file <report-file>` and explain the anchoring failure.
The posted verdict must identify the independent reviewer and reviewed revision.
