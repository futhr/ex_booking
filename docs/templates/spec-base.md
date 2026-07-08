---
ex_booking:
  id: "SP.[NUMBER]"
  title: "[Title]"
  domain: booking
  status: draft
  priority: medium
  created: "[YYYY-MM-DD]"
  updated: "[YYYY-MM-DD]"
  tags: []
  depends_on: []
---

# SP.[NUMBER] — [Title]

One-paragraph statement of what this spec makes normative and where it sits in
the kernel. State the status word (normative / informative) in prose if useful.

## Overview and Scope

- What this spec covers.
- What it explicitly does not (link the responsible layer: consumer / adapter).

## Data Model

Structs and types introduced or referenced (link `SP.01` rather than
redefining). Use fenced `elixir` blocks for struct shapes; every field is public
API.

## Algorithms

The exact, deterministic procedure. Prefer pseudocode or `elixir` for the
normative steps. Call out any DST / timezone / ordering rule explicitly — the
kernel is deterministic and slot interval is independent of duration.

## Public API

`@spec`-shaped signatures for the facade functions this spec defines. Reference
the common-options table in `SP.02` instead of repeating it.

## Error Vocabulary

Tagged tuples this spec adds to the stable vocabulary (`SP.02`). Additions are
minor-version changes; removals/renames are breaking.

## Testing Strategy

Doctests, example tests, StreamData properties, and DST fixtures required for
this behavior (per `SP.06`). Name the laws that must hold.

## Sources

Research notes (`R.NN`), sibling specs, and any primary references
(RFCs, standards). No copyleft code may be copied or paraphrased in.
