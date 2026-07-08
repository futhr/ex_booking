---
ex_booking:
  id: "R.[NUMBER]"
  topic: "[Topic]"
  category: research
  status: in-progress
  created: "[YYYY-MM-DD]"
  updated: "[YYYY-MM-DD]"
  decision: pending
  tags: []
---

# R.[NUMBER] — [Topic]

Background, not normative. Record *why*, not *how* — implementation detail lives
in `docs/specs/`. Name no private consumer application; describe the market
shape, not a vendor.

## Executive Summary

The bottom line in a few sentences: what was investigated and what was decided.

## Research Question

The specific question(s) this note answers.

## Methodology

Sources consulted and how they were weighed. Prefer primary sources (RFCs,
standards, package docs, release data as context only). Judge libraries by
protocol/implementation fit, never by release recency alone.

## Findings

### [Source or Approach]

What it showed, with evidence.

## Comparative Analysis

| Criterion | Option A | Option B | Option C |
|---|---|---|---|
|  |  |  |  |

## Recommendation

**Decision:** [adopted / rejected / deferred]

**Rationale:** why.

## Impact on ExBooking

- Specs to create/update: `SP.NN`.
- Modules affected: `lib/ex_booking/...`.
- Tasks: link `docs/tasks/booking-tasks.md` (do not enumerate work here).
- Breaking changes: yes/no.

## Sources

Primary references, with enough detail to re-find them. No copyleft code copied
or paraphrased into this MIT library.
