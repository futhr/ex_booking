---
name: review
description: Review booking-kernel changes for correctness or investigate bugs, coverage gaps, architecture, and public or Hex-consumer compatibility. Apply when review is requested or changed temporal, capacity, assignment, or lifecycle behavior needs inspection before delivery; exclude prose-only cleanup.
user-invocable: false
---

# Review kernel behavior and consumer boundaries

Inputs: the requested review scope or change diff, owning specs, implementation,
tests, and available consumer evidence. Output: actionable findings with file
locations, concrete consequences, supporting evidence, and unverified boundaries.

Trace affected public functions and structs through the facade, domain modules,
callers, types, examples, and package contents. Read the owning specifications
via the [spec index](../../../docs/README.md#spec-index), selecting only relevant
sections. Compare actual behavior with the repository contract; flag disagreements
explicitly instead of silently choosing an authority.

Inspect the mechanisms touched by the change:

- Interval arithmetic: half-open adjacency, complete subtraction, normalization,
  containment, and comparisons by UTC instant, including microseconds.
- Schedule and recurrence: local-day and overnight boundaries, blackouts,
  ambiguity resolution, and each mechanism's gap policy. Availability snaps
  gaps forward; recurrence skips nonexistent local times without consuming COUNT.
- Slots and conflicts: independent grid step and duration, alignment, deduplication,
  buffer equivalence, requested-slot containment, and stable ordering.
- Capacity and assignment: peak concurrent reservation sums, end/start adjacency,
  distinct resource identities, collective/preferred-resource behavior, exact
  ranking, missing fairness, numeric precision, and total tie-breaks.
- Public input and lifecycle: validated nested facts and options, the owning
  API's tagged-error contract, Decision rejection statuses, hold consistency,
  event payloads, and ordered intent tuples. A domain module may return reasons
  internally; do not confuse that with the facade's Decision contract.
- Consumer boundary: side effects remain consumer-owned; inspect calls and
  dependencies for hidden clock, process, I/O, or configuration coupling.
  Snapshot checks cannot establish atomic persistence guarantees.

Assess assertions against plausible broken behavior. An executed line, coverage
percentage, or matching search result does not establish correctness. Check for
vacuous properties, conditional skips, weakened assertions, broad exclusions,
and tests that only mirror the implementation. Use focused probes when warranted;
do not impose mutation testing on every change.

Check affected docs, task acceptance items, notebooks, and package compatibility.
Distinguish an internal test, extracted-archive consumer, and real downstream
application. Report only observed gate results; use
[SP.07](../../../docs/specs/SP.07-validation.md) to identify missing proof.
Rank findings by concrete consequence and confidence, without invented scores.
If no issue is found, state the reviewed scope and remaining limitations.
