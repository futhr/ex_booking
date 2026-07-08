---
ex_booking:
  id: "R.03"
  topic: "Post-build kernel audit against base research"
  category: research
  status: complete
  created: "2026-07-08"
  updated: "2026-07-08"
  decision: adopted
  tags: ["audit", "lifecycle", "alternatives", "kernel-boundary"]
---

# R.03 — Post-build Kernel Audit Against Base Research

Background, not normative. This note records the post-build audit prompted by the
base scheduling research and maps the result back to `docs/specs/` and
`docs/tasks/booking-tasks.md`.

## Executive Summary

The initial milestone checklist covered the core temporal, assignment, lifecycle,
and standards work, but two kernel-level gaps were still real:

1. rejected booking decisions promised nearest alternatives but did not compute
   them; and
2. cancellation, hold expiry, and no-show events existed as vocabulary without
   pure transition helpers that produced those events and intents.

Both are now adopted into the kernel because they are pure, reusable booking
semantics. Payment state, provider contracts, Ash wrappers, routing forms,
analytics, GTM/CRM enrichment, and AI remain outside the kernel because adding
any of them would turn this package into an orchestration layer.

## Research Question

After completing the task checklist, did the kernel miss any important capability
that the base scheduling research identifies as part of a reusable 2026 booking
kernel rather than consumer orchestration?

## Methodology

The audit reread the original deep-research reports and the consolidated `R.01`
research note, then compared their kernel recommendations against the current
public API, specs, and tests. The boundary rule was strict: only deterministic,
side-effect-free booking semantics belong here.

## Findings

### Adopted Kernel Gaps

- **Rejected-decision alternatives** — mature booking flows need useful fallback
  slots after a conflict or policy rejection. This belongs in the kernel when the
  caller supplies an explicit search horizon, because it uses the same
  deterministic availability pipeline as slot search.
- **Lifecycle transition templates** — cancellation, hold expiry, and no-show are
  canonical booking transitions. The consumer still owns state and execution, but
  the kernel should return stable events/intents for these transitions.

### Deliberately Not Adopted

- **Payment state semantics** — the research repeatedly notes payments and billing
  as adjacent to scheduling, but `R.01` and `SP.05` choose event-driven billing
  outside the kernel. The kernel emits booking events; billing consumes them.
- **Provider behaviors** — calendar, CRM, conferencing, notification, analytics,
  and billing providers require I/O, credentials, retries, and operational state.
- **Ash wrapper** — useful for consumers, but it is an application-model layer and
  would add framework coupling to the pure package.
- **Routing forms / enrichment / AI** — these are orchestration and product
  differentiation layers. The kernel receives their output only as opaque
  `routing_context`, scorer functions, preferred resource ids, or normalized busy
  intervals.

## Recommendation

**Decision:** adopted.

**Rationale:** add missing pure booking semantics, but keep the package small and
side-effect-free. This aligns the implementation with the research without
collapsing the kernel/orchestration boundary.

## Impact on ExBooking

- Specs updated: `SP.01`, `SP.02`, `SP.05`, `SP.07`.
- Modules affected: `lib/ex_booking.ex`.
- Tasks: `docs/tasks/booking-tasks.md`, milestone M5.
- Breaking changes: no.

## Sources

- `docs/research/R.01-booking-space-and-kernel-rationale.md`.
- Base deep-research reports supplied for the audit on 2026-07-08.
- Normative specs under `docs/specs/SP.NN-*.md`.

No copyleft source code was copied or paraphrased into this MIT library.
