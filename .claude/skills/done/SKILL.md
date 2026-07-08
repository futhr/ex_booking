---
name: done
description: Run ExBooking's full quality gate after implementation, docs changes, or before committing. Use when work is finished, ready to commit, ship-ready, or whenever the user asks for clean gates.
allowed-tools: Bash(mix *), Bash(git *), Bash(rg *)
---

# Done

Run the full gate. Everything must be clean before declaring a task done or
committing. `mix check` runs the whole pipeline; the individual commands make
failures easier to diagnose.

## Gate

```bash
git diff --check
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix deps.audit
mix dialyzer
mix doctor
mix docs
mix test --cover
mix check
```

## Rules

- `mix doctor` must report 100% moduledoc and ≥80% `@spec` coverage.
- `mix test --cover` must hold ≥95% line coverage (`coveralls.json`; `test/support`
  excluded).
- New algebra/slotting behavior needs StreamData properties **and** DST fixtures
  (`Europe/Stockholm`, `America/New_York`), not just example tests.
- If any gate fails, the task is not done — fix and re-run.
