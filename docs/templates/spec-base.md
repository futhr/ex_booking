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

Make the document usable without the originating chat or research narrative.
Distinguish a normative target from currently executable APIs and evidence.
Use stable requirement/case IDs for substantial additions.

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

## Bounds, Continuation and Compatibility

Define defaults, unknown/duplicate fields, native-struct validation, precision,
ordering and finite work/input/output limits where applicable. Specify empty
results and retries. For continuation, bind the complete semantic query and
define stale/tampered input and exhaustion. State which existing public behavior
is unchanged. Pure kernel results cannot authorize or commit consumer effects.

## Testing Strategy

Doctests, example tests, StreamData properties, and DST fixtures required for
this behavior (per `SP.07`). Name the laws that must hold.

Map each requirement to reproducible input, expected observation and a concrete
falsifier. Keep the oracle independent of the production mechanism. Planned
cases remain obligations until commands and outcomes are actually observed.

## Sources

Research notes (`R.NN`), sibling specs, and any primary references
(RFCs, standards). No copyleft code may be copied or paraphrased in.
