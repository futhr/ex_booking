---
name: booking-boundary-proof
description: "Apply automatically when ExBooking changes a public function, struct, temporal rule, availability or slot algorithm, conflict or assignment behavior, lifecycle decision, intent, notebook, or Hex package surface. Prove purity, determinism, temporal correctness, and consumer compatibility."
---

# Booking boundary proof

Trace the public facade through the owning pure module and every caller, type/spec, example,
notebook, and packaged file. Confirm the caller still owns persistence, processes, HTTP, clock,
randomness, auth, state machines, jobs, and UI.

Prove deterministic ordering, interval algebra, slot-step independence from duration, boundary
inclusion/exclusion, and DST gaps/ambiguities in Stockholm and New York where applicable. Use
StreamData properties for algebraic behavior plus focused examples for named edge cases.

Check the published API and notebook outputs, not only internal tests. Never copy or closely
paraphrase copyleft source, add a dependency without discussion, or hide a spec/code mismatch.
