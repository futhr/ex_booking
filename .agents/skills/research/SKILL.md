---
name: research
description: Resolve booking design questions that depend on external scheduling standards, recurrence libraries, timezone/DST behavior, or Elixir package capabilities. Use primary sources and compare them with the kernel and Hex-consumer contracts; exclude repository-only reviews and routine documentation lookups.
user-invocable: false
---

# Research a booking design decision

Inputs: a concrete design question, relevant repository contracts and behavior,
and current primary sources. Output: a supported decision or explicit unresolved
choice, with sources, tradeoffs, and the owner of any follow-on work.

1. Read related material through the
   [research index](../../../docs/research/README.md), then the affected specs,
   code, and tests. Identify the decision that external evidence must resolve.
2. Consult primary standards, official library documentation, implementation,
   and release data as needed. Record source dates or versions and distinguish
   shipped capabilities from proposals. Prefer protocol and implementation fit
   over package recency.
3. Compare alternatives against the actual kernel boundary, determinism,
   timezone rules, runtime dependencies, and packaged-consumer requirements.
   Resolve conflicting or superseded evidence; state inferences and gaps.
   Request consumer evidence only when the conclusion depends on it.
4. Recommend adoption, rejection, deferral, or a concrete validation step.
   Explain the deciding evidence, what could invalidate the conclusion, and
   which repository or consumer owns the next action.
5. When a project research note is part of the authorized deliverable, use
   [research-base.md](../../../docs/templates/research-base.md) and the existing
   `R.NN-slug.md` convention under `docs/research/`. Follow its `ex_booking`
   metadata and sections. If the user requests chat-only findings, keep all
   findings and sources in chat.

Research explains the decision; accepted observable behavior belongs in specs.
Link follow-on implementation to the
[task list](../../../docs/tasks/booking-tasks.md) instead of adding a second
roadmap to a research note. External evidence alone does not authorize source,
dependency, configuration, or consumer changes.
