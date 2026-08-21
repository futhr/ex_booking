---
name: booking-diagnosis-loop
description: "Apply automatically when an ExBooking test, property, DST fixture, ordering assertion, notebook, or consumer example fails. Reduce the temporal case, identify the violated invariant, and fix the pure owning algorithm."
---

# Booking diagnosis loop

Record exact normalized inputs, timezone database result, interval boundaries, duration, step,
resource ordering, and observed output. Shrink to the smallest counterexample; preserve the random
seed for property failures.

Test one hypothesis at a time: normalization, timezone conversion, gap/ambiguity policy, interval
algebra, conflict predicate, candidate ordering, assignment tie-break, or lifecycle rule. Fix the
owning pure function, not a caller-side reorder or a fixture exception.

Retain the minimized example and a general property when the defect represents an invariant.
Re-run notebooks/package evidence when the public surface changes.
