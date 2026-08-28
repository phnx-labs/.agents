# Mission

**Your fleet's product mission — what this company is building, who the customers are,
and the current #1 priority — is _project context_, not methodology.** It does not live
in this public system layer, because it is specific to one operator and often
confidential.

It belongs in the **user layer**: `~/.agents/rules/subrules/mission.md`. That file
compiles into your `CLAUDE.md` ahead of this one and, because a same-named subrule wins
wholesale, **replaces this placeholder entirely** on a machine that has it. So:

- **If a real mission is present above** (from the user layer), that is your mission.
  Internalize it. Treat it as the priority every task ladders up to, and check whether
  the work in front of you actually advances it.
- **If only this placeholder is present**, the operator has not written a mission yet.
  Don't assume the work is generic infrastructure — ask what the product, the customers,
  and the #1 goal are before spending real effort, and offer to capture the answer as a
  user-layer `mission.md` so every future agent boots with it.

Keep a mission rule to one tight screen: what / who / why / what's P0. Volatile specifics
(this quarter's target, named accounts) belong in the tracker, recalled on demand — not
paid on every boot.
