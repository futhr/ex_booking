---
ex_booking:
  template_type: task
  template_version: "1.1.0"
---

# [Project] Tasks

Single roadmap for this repo. Specs explain code contracts; this file tracks
planned, in-progress, and completed repo work.

Legend:

```text
[x] complete
[ ] planned / not started
[~] in progress
```

## Operating Rules

```text
[ ] Read CLAUDE.md before changing code.
[ ] Keep specs descriptive, not roadmap-shaped.
[ ] Keep this file as the single roadmap.
[ ] Update the matching SP.NN spec with behavior changes.
[ ] Run mix check --no-retry before handoff.
```

## Quality Gates

```text
[ ] mix format --check-formatted
[ ] mix compile --warnings-as-errors
[ ] mix credo --strict
[ ] mix deps.audit
[ ] mix dialyzer
[ ] mix doctor
[ ] mix docs
[ ] mix test --cover
[ ] mix check --no-retry
```

## SP.NN — [Spec Name]

Spec: `docs/specs/SP.NN-[slug].md`
Files: `[paths]`

```text
[ ] [Concrete repo task]
[ ] [Concrete repo task]
```

## Open Roadmap

```text
[ ] [Next repo task, or "No in-repo tasks are currently open."]
```

## Delegated Outside This Repo

```text
[-] [External concern owned by consumer/adapters]
```
