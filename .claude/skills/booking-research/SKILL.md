---
name: booking-research
description: "Apply automatically when an ExBooking decision about scheduling standards, calendaring, recurrence libraries, time-zone/DST behavior, or the Elixir ecosystem depends on facts outside the repository. Use primary sources, compare tradeoffs against booking invariants and Hex consumers, cite dates, and record the resulting decision under docs/research."
---

# Booking Research

Research notes live under `docs/research/` as `R.NN-slug.md` and start from
`docs/templates/research-base.md`.

Write only under `docs/research/`. Do not modify source, tests, config, or
quality-ignore files from this skill.

## Required

- `ex_booking:` research frontmatter (`id`, `topic`, `category`, `status`,
  `created`, `updated`, `decision`, `tags`).
- Executive Summary, Research Question, Methodology, Findings, Comparative
  Analysis, Recommendation (with an explicit `Decision:`), Impact on ExBooking,
  Sources.

## Constraints

- Background only — record *why*, not *how*. Implementation detail belongs in
  `docs/specs/`.
- Prefer primary sources (RFC 5545/8984, package docs, Hex release data as
  context only). Judge recurrence libraries by protocol/implementation fit, not
  release recency.
- Name no private consumer application or vendor product; describe the market
  shape.
- No copyleft code copied or paraphrased in.
- Link to `docs/tasks/booking-tasks.md` for follow-on work; do not enumerate
  implementation tasks inside the research note.
