---
name: implement
description: Implement booking-kernel behavior changes or diagnose failures in temporal math, availability, slotting, conflicts, assignment, policy, lifecycle, calendar imports, notebooks, or packaged-consumer examples. Use for affected code and behavioral tests, not guidance-only edits.
user-invocable: false
---

# Implement and diagnose kernel behavior

Inputs: the requested behavior or observed failure, affected code/tests, and the
owning spec and task entry. Output: the scoped implementation, discriminating
tests, aligned documentation/tasks, and actual validation results in the handoff.

1. Read the relevant sections of the
   [task list](../../../docs/tasks/booking-tasks.md) and owning spec. Use
   [SP.01](../../../docs/specs/SP.01-data-model.md) for struct contracts and
   [SP.02](../../../docs/specs/SP.02-public-api.md) for options and error vocabulary.
   Check task dependencies before implementing dependent behavior.
2. Trace the affected facade call into its owning domain module, callers, and
   tests. Inspect notebooks and package files only when the exposed behavior or
   consumer surface changes. Reuse the existing interval operations.
3. For a behavioral fix or addition, run a minimal test against current code.
   Confirm it fails at the intended assertion. If it already passes, determine
   whether the behavior is implemented or the test fails to distinguish the
   requested change. Do not manufacture a failure for a behavior-preserving edit.
4. For a failure, capture normalized inputs, interval boundaries, timezone
   conversion results, duration/grid step, ordering, and actual output as relevant.
   Preserve the seed for property failures and shrink the case. Test a causal
   hypothesis with a discriminating probe before patching. If fixes do not explain
   the failure, revisit the contract and algorithm instead of accumulating patches.
5. Change the owning operation and rerun the same test. Retain a minimized
   regression and add a general property when the defect violates an invariant.
   Do not mask an algorithm defect with caller-side reordering or fixture exceptions.

Load mechanism-specific contracts as needed:

- [SP.03](../../../docs/specs/SP.03-algorithms.md): half-open boundaries,
  containment, buffer application, slot grids, overnight windows, and peak
  simultaneous seat consumption. Sequential reservations are not simultaneous.
- [SP.04](../../../docs/specs/SP.04-assignment.md): exact ranking, missing
  fairness values, numeric precision, and deterministic tie-breaks.
- [SP.05](../../../docs/specs/SP.05-lifecycle-and-events.md): transition inputs,
  hold handling, events, and ordered intent tuples.
- [SP.06](../../../docs/specs/SP.06-standards-interop.md): supported calendar
  subsets and recurrence semantics. Do not apply availability-window gap
  snapping to recurrence; nonexistent recurrence times are skipped.
- [SP.07](../../../docs/specs/SP.07-validation.md): required properties, DST
  fixtures, public-input checks, and consumer verification.

Update the owning spec and affected task acceptance items with the behavior.
Refresh relevant examples and notebook outputs. Mark tasks complete only from
observed evidence, and report focused results and unavailable proof at delivery.
