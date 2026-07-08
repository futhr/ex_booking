# Quality Gates Standard

The gate that must be green before any change is declared done or committed.
`SP.06` is the normative testing strategy; this restates the enforced bar.

## Gate Commands

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix deps.audit
mix dialyzer
mix doctor
mix docs
mix test --cover
mix check          # ex_check runs all of the above
```

## Enforced Bars

- **Docs**: `mix doctor` — 100% moduledoc coverage, ≥80% `@spec` coverage.
  Every public function has a `@doc`, an `@spec`, and a doctest.
- **Coverage**: `mix test --cover` — ≥95% line coverage (`coveralls.json`).
  `test/support` is excluded.
- **Types**: `mix dialyzer` clean. `:no_extra_return` is a temporary flag while
  stubs exist (`SP.07` v0.1); remove it once real returns land.
- **Style**: `mix credo --strict` clean, including `Readability.Specs`.

## Required Test Kinds

- **Doctests** — happy path for every public function.
- **Example tests** — one `*_test.exs` per module; edge cases, error vocabulary,
  each `Decision.status` branch.
- **Property tests** (StreamData) — the interval algebra laws (`SP.03` §1) and
  the assembly/validation buffer equivalence (`SP.03` §6).
- **DST fixtures** — `Europe/Stockholm` and `America/New_York`, covering
  spring-forward gaps, fall-back overlaps, and midnight-crossing windows.
- **Determinism golden tests** — stable output ordering for fixed inputs.
