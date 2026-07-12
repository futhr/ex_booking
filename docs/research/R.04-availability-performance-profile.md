---
ex_booking:
  id: "R.04"
  topic: "Availability performance profile"
  category: performance
  status: accepted
  created: "2026-07-12"
  updated: "2026-07-12"
  decision: "Use linear collective intersection and order-preserving reverse reason accumulation; retain the current recurrence walk because measured production horizons do not justify a DST- and COUNT-sensitive fast-forward path."
  tags: ["availability", "intervals", "performance", "determinism"]
---

# R.04 — Availability Performance Profile

## Executive Summary

Measured profiles found two material algorithmic costs in availability assembly:
Cartesian collective intersection and repeated list append while gathering
rejection reasons. The first grows with the product of interval-set sizes; the
second becomes quadratic in large resource pools. Linear equivalents preserve
the existing result and deterministic order.

A third suspected cost—walking daily or weekly recurrence from a distant start—
remained under 35 ms even across a 100-year gap. A shortcut would need to retain
absolute `COUNT` ordinals, overlap-before-horizon behavior, and zoned wall-time
semantics across DST. That complexity is not justified by the measured booking
horizons.

## Research Question

Which suspected large-horizon or large-resource costs are material in the pure
kernel, and which optimizations preserve interval metadata, recurrence semantics,
and deterministic output?

## Methodology

The profile used release-equivalent compiled kernel functions through `mix run`,
with one warm-up followed by five to nine samples. Median monotonic wall time and
BEAM reductions were recorded. Inputs scaled independently across resource count,
daily interval count, and the distance between recurrence start and query horizon.

Candidate algorithms were isolated and compared for exact structural equality,
not merely equivalent timestamps. The final tests compare linear intersection to
a retained Cartesian reference over generated normalized interval sets and assert
reason order on a 1,000-resource regression input.

## Findings

### Collective interval intersection

The former Cartesian implementation reached about 304 ms and 130 million
reductions for ten resources with 365 daily intervals. An isolated two-pointer
walk took roughly 134 microseconds for two 365-interval sets versus 31.5 ms for
the Cartesian reference. At 1,000 intervals the isolated speedup exceeded 600×.

The correct linear walk clips the current pair, advances the interval ending
first, advances both on equal ends, accumulates in reverse, and performs a final
defensive merge. This is `O(A + B)` per pair after normalization.

### Reason accumulation

Repeated `acc ++ reasons` reached about 795 ms for 16,000 chunks, while reverse
accumulation followed by one reversal took under 0.3 ms. Reversing each small
resource chunk into an accumulator and reversing once preserves resource order
and the order within each resource.

### Distant recurrence starts

Daily and weekly recurrence expansion across a 100-year gap took approximately
33 ms and 28 ms respectively. A safe jump cannot be based only on elapsed days:
it must preserve an occurrence's absolute ordinal for `COUNT`, include an
occurrence that starts before but overlaps the query horizon, and resolve local
wall times across DST exactly as the sequential implementation does.

## Comparative Analysis

| Candidate | Measured impact | Semantic risk | Verdict |
|---|---:|---:|---|
| Two-pointer interval intersection | material at annual horizons | low; reference-equivalence testable | implement |
| Reverse reason accumulation | material for large pools | low; order-equivalence testable | implement |
| Recurrence fast-forward | small in measured horizons | high for COUNT/DST/overlap | retain sequential walk |

## Recommendation

**Decision: use normalized two-pointer intersection and order-preserving reverse
reason accumulation, and do not add a recurrence fast-forward path.**

This closes the measured performance gap without adding a speculative branch to
the most semantically sensitive calendar code. If consumer profiles later show a
material recurrence cost, the evidence must include the actual horizon and rule
distribution and any replacement must be reference-tested for `COUNT`, `UNTIL`,
overlap, and DST behavior.

## Impact on ExBooking

- `ExBooking.Interval.intersect/2` becomes the normative linear set operation.
- Collective availability uses it instead of building a Cartesian product.
- `:one` and `:pool` validation preserve the existing reason order with linear
  accumulation.
- `SP.03` records both complexity and ordering requirements.
- The completed work is tracked in `docs/tasks/booking-tasks.md`.
- No dependency, process, clock, I/O, or host-specific behavior is added.

## Sources

- [Erlang efficiency guide: list handling](https://www.erlang.org/doc/system/listhandling.html)
- [Elixir `Enum` documentation](https://hexdocs.pm/elixir/Enum.html)
- [RFC 5545 recurrence rules and `COUNT`](https://www.rfc-editor.org/rfc/rfc5545.html#section-3.3.10)
- Local benchmark harness and results recorded in this note's Methodology and Findings
- `docs/specs/SP.03-algorithms.md`
- `docs/tasks/booking-tasks.md`
