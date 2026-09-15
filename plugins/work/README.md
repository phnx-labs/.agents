# work plugin

Deliver work across coding, research, design, content, browser, and native app tasks.
Work owns delivery and Git workflows; the [code plugin](../code/README.md) owns engineering
assessment, review, refactoring, and codebase learning.

| Command | Capability | Source |
|---|---|---|
| `/work:loop` (`/loop`) | Deliver a ticket, branch, PR, or queue; spread independent work across the fleet. `triage` decides keep-and-schedule or cancel. | [Command](commands/loop.md) · [Skill](skills/loop/SKILL.md) |
| `/work:commit` (`/commit`) | Commit and push cohesive changes to code, documentation, assets, or configuration. | [Command](commands/commit.md) · [Skill](skills/commit/SKILL.md) |
| `/work:dispatch` (`/dispatch`) | Discover, route, and verify one unit of work. | [Command](commands/dispatch.md) · [Skill](skills/dispatch/SKILL.md) |
| `/work:resume` (`/resume`) | Reconstruct one project's sessions, PRs, worktrees, and tickets, then resume unfinished work on workers. | [Command](commands/resume.md) · [Skill](skills/resume/SKILL.md) |
| `/work:demo` (`/demo`) | Demonstrate the installed or live result against original intent with real inputs and evidence. | [Command](commands/demo.md) · [Skill](skills/demo/SKILL.md) |

Commands and top-level aliases route to the same portable skills. Harnesses without
commands use those skills directly. `work:loop` owns both engineering and mixed queues;
there is no separate engineering loop. It composes `code:review` when engineering review
is needed and follows the target repository's merge and release policy.

Use `dispatch` for one task, `resume` to recover a project's in-flight work, and `loop` to
keep delivering a selected queue. A plain loop does not make board-wide cancellation
decisions; invoke `loop triage` for that. `demo` verifies and presents what actually shipped.
