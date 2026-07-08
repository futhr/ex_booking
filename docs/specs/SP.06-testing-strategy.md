---
ex_booking:
  id: "SP.06"
  title: "Testing Strategy"
  domain: booking
  status: normative
  priority: medium
  created: "2026-07-08"
  updated: "2026-07-08"
  tags: ["testing", "property-tests", "doctests", "dst-fixtures", "coverage"]
  depends_on: ["SP.03"]
---

# SP.06 — Testing Strategy

The kernel's purity makes it exhaustively testable — no mocks, no sandboxes, no
async setup. Test kinds follow the conventions already used in this codebase
lineage (ExUnit, doctests, StreamData properties, ExCoveralls gate).

## Layers

1. **Doctests** — every public function documents and verifies its happy path.
   Doctests are formatted by `doctest_formatter`.
2. **Example tests** (`test/ex_booking/*_test.exs`) — one file per module;
   edge cases, error vocabulary, and each `Decision.status` branch.
3. **Property tests** (StreamData) — the interval algebra laws from SP.03 §1:
   - `overlaps?/2` symmetry
   - `subtract/2` results are disjoint, contained in the minuend, and never
     overlap the subtrahend
   - `merge/1` idempotence and normal form (sorted, disjoint, non-adjacent)
   - `clip/2` containment in both operands
   - assembly/validation buffer equivalence (SP.03 §6): inflating busy at
     assembly time and inflating the slot at validation time agree
   - slot generation: every emitted slot fits inside its free interval, starts
     on the grid, and consecutive starts differ by exactly the step
4. **DST corpus** — fixture module (`test/support/dst_fixtures.ex`) pinning the
   spring-forward and fall-back transitions for at least `Europe/Stockholm` and
   `America/New_York`. Any timezone-sensitive function must have cases for:
   - a window containing a spring-forward gap (slot snaps forward, no phantom slots)
   - a window containing a fall-back overlap (first occurrence chosen, no duplicate slots)
   - a window crossing midnight across a transition
5. **Determinism checks** — golden tests asserting stable output ordering for
   fixed inputs.

## Generators

`test/support/generators.ex` provides StreamData generators for intervals
(bounded horizon, minute-aligned), availability rules, resources with busy sets,
and meeting types (duration/step combinations including step < duration,
step == duration, step > duration).

## Builders

`test/support/builders.ex` provides `build(:rule)`, `build(:resource)`,
`build(:meeting_type)`, `build(:request)` with override maps — plain functions,
no factory library.

## Gates

- `mix test --cover` enforces ≥ 95% line coverage (coveralls.json); test/support
  is excluded from coverage.
- `mix check` (ex_check) runs compile `--warnings-as-errors`, format, credo
  `--strict`, deps.audit, dialyzer, doctor (100% moduledoc), docs build, and the
  test suite — all must pass in CI on Elixir 1.18/1.19/1.20 × OTP 28/29.

## Reference scenarios (to port as example tests during v0.1)

Behavioral scenarios worth encoding, drawn from the research corpus (concepts
only — no code from AGPL sources): back-to-back bookings with zero buffers are
legal; buffers block adjacency but not day edges; a 30-minute meeting on a
15-minute grid in a 60-minute window yields exactly three slots; lead time is
evaluated against caller-supplied `now`, never wall clock.
