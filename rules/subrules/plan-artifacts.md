# Plans Are Committed Artifacts, Linked Both Ways to Their Tickets

In product repositories, commit the rendered HTML plan with the feature under `.agents/plans/`; keep scratch and worktrees ignored, and exempt the npm-shipped `.agents/.system` mirror. A plan-and-build session uses one worktree and one PR. Tickets link to the rendered plan, and the plan’s Tracking section links back to every task it created.
