---
ex_booking:
  template_type: task
  template_version: "1.0.0"
---

# [Project] Tasks

Canonical execution checklist. One file, milestone sections in strict order.
Every accepted design in `docs/specs/` has a task entry here before broad
implementation.

## Progress Summary

| # | Milestone | Done | Total | % | Status |
|----|-----------|-----:|------:|-----:|-------------|
| [ID] | [Name] | [N] | [N] | [%] | [Planned/In progress/Complete] |
| — | **Total** | **[N]** | **[N]** | **[%]** |  |

## Operating Rules

- Read `CLAUDE.md` first; it is the canonical contract.
- Purity and determinism are non-negotiable (no clock, no I/O, no randomness).
- Update the spec in the same change as the code.

## Mandatory Gates For Every Commit

- [ ] `mix format --check-formatted`.
- [ ] `mix compile --warnings-as-errors`.
- [ ] `mix credo --strict`.
- [ ] `mix deps.audit`.
- [ ] `mix dialyzer`.
- [ ] `mix doctor` (100% moduledoc, ≥80% `@spec`).
- [ ] `mix docs`.
- [ ] `mix test --cover` (≥95%).
- [ ] `mix check` clean.

## [MILESTONE-ID] — [Milestone Name]

> Specs: `SP.NN`.
> Depends on: [prior milestone].
> Exit criteria: [what "done" means; `mix check` clean].

- [ ] [MILESTONE-ID].NN [One-line task summary].
  - Spec: `docs/specs/SP.NN-[slug].md` — [section].
  - AC: [specific, testable criterion].
  - AC: [error/edge behavior].
  - Tests: [doctest / property / DST fixture / example].
