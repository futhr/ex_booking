---
name: spec
description: Define or revise observable booking behavior in docs/specs before implementing a new design or changing a contract. Use for temporal, timezone/DST, availability, capacity, assignment, lifecycle, calendar interop, or public API decisions; exclude routine prose edits and agent guidance.
user-invocable: false
---

# Specify observable kernel behavior

Inputs: the requested contract change, current specs/code/tests, and relevant
design evidence. Output: the owning normative spec changes, linked task acceptance
criteria, and explicit unresolved decisions where evidence or authority is missing.

1. Locate the owning spec through the
   [spec index](../../../docs/README.md#spec-index). Compare its current contract
   with implementation and tests, and surface disagreements.
2. Revise the existing owner rather than creating a competing specification.
   For a new spec, use [spec-base.md](../../../docs/templates/spec-base.md), its
   `ex_booking` metadata, the `SP.NN-slug.md` convention, and a matching H1.
   Keep dependency links accurate.
3. Define accepted inputs, outputs, errors, boundary cases, deterministic
   ordering, and consumer responsibilities. Use exact algorithms or pseudocode
   only where needed to make behavior unambiguous.
4. Specify mechanism-specific temporal behavior: UTC versus local-day arithmetic,
   interval inclusion, DST gaps/ambiguities, independent slot grids, buffers,
   concurrent seat accounting, and precision where affected. For lifecycle or
   concurrency changes, identify supplied snapshot facts and consumer-owned effects.
5. Reference [SP.01](../../../docs/specs/SP.01-data-model.md) for shared structs,
   [SP.02](../../../docs/specs/SP.02-public-api.md) for public API/options/errors,
   and [SP.07](../../../docs/specs/SP.07-validation.md) for discriminating examples,
   properties, DST fixtures, and consumer checks. Extend those owners when their
   contracts change instead of duplicating them.
6. Link supporting research or standards only where they inform a decision.
   Add or update work and acceptance criteria in the
   [task list](../../../docs/tasks/booking-tasks.md). Keep roadmap state there.

Do not turn an unresolved product choice into normative behavior. Explain the
missing decision and continue independent work. When implementation is also
authorized, keep the contract, tests, and code aligned in the same change.
