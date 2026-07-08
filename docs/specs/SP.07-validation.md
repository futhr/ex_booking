---
ex_booking:
  id: "SP.07"
  title: "Validation"
  domain: booking
  status: normative
  priority: high
  created: "2026-07-08"
  updated: "2026-07-08"
  tags: ["tests", "quality-gates", "coverage", "properties"]
  depends_on: ["SP.03"]
---

# SP.07 — Validation

This spec describes the validation setup for this repo. It is not a roadmap;
roadmap state lives only in `docs/tasks/booking-tasks.md`.

## Test Layout

```text
test/ex_booking_test.exs              facade behavior and lifecycle examples
test/ex_booking/*_test.exs            module-level example tests
test/support/builders.ex              plain struct builders
test/support/generators.ex            StreamData generators
test/support/dst_fixtures.ex          pinned DST transition corpus
```

## Required Test Styles

- **Doctests** for public examples on public modules/functions.
- **Example tests** for error vocabulary, lifecycle branches, and edge cases.
- **Property tests** for interval algebra and slotting invariants.
- **DST fixtures** for timezone-sensitive behavior in `Europe/Stockholm` and
  `America/New_York`.
- **Determinism checks** for stable ordering and total tie-breaks.

## Required Properties

The property suite must cover:

- `Interval.overlaps?/2` symmetry;
- `Interval.subtract/2` containment and disjointness;
- `Interval.merge/1` idempotence and normal form;
- `Interval.clip/2` containment;
- availability/validation buffer equivalence;
- slot starts fit inside free intervals and follow the grid step.

## Quality Gates

`mix check --no-retry` is the repo-level gate. It runs or wraps:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix deps.audit
mix dialyzer
mix doctor
mix docs
mix test --cover
```

Coverage must remain at or above 95% line coverage with `test/support` excluded.
`mix doctor` must keep 100% moduledoc and public spec coverage.

## Change Rule

Any change that touches behavior must update the matching spec, task checklist,
and tests in the same commit. Do not add dependencies or integration behavior to
satisfy tests; keep the kernel pure and push effects to consumers.
