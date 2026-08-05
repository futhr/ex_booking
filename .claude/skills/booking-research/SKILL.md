---
name: booking-research
description: Create or update ExBooking research notes under docs/research with primary sources, tradeoff analysis, and an explicit decision. Use for scheduling-market, calendaring-standards, recurrence-library, or Elixir-ecosystem research.
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(rg *), Bash(sed *), WebSearch, WebFetch
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
