---
name: booking-spec
description: Create or update ExBooking normative specs under docs/specs. Use before implementing temporal, availability, slotting, assignment, policy, or lifecycle changes.
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(rg *), Bash(sed *)
---

# Booking Spec

Specs live under `docs/specs/` as `SP.NN-slug.md` and start from
`docs/templates/spec-base.md`.

Write only under `docs/specs/` and `docs/tasks/booking-tasks.md`. Do not modify
source, tests, config, or quality-ignore files from this skill.

## Required

- `ex_booking:` YAML frontmatter (`id`, `title`, `domain`, `status`, `priority`,
  `created`, `updated`, `tags`, `depends_on`).
- H1 mirrors the id: `# SP.NN — Title`.
- Deterministic, exact algorithms — pseudocode or `elixir` for normative steps.
- Explicit DST / timezone / ordering rules where relevant.
- Error vocabulary additions cross-referenced to `SP.02`.
- Testing strategy (doctest / property / DST fixture) per `SP.06`.
- Sources: link `R.NN` and any RFC/standard.

## Constraints

- Spec is source of truth: it changes in the same commit as the code.
- Slot interval independent of duration; kernel stays pure and deterministic.
- No copyleft code copied or paraphrased (`R.01` §5).
- Add or update a task in `docs/tasks/booking-tasks.md` when the spec creates
  work, and keep the `depends_on` graph accurate.
