---
name: unslop
description: Cut AI tells from human-facing prose while preserving technical, legal, product, and domain precision. Use when writing or editing README, docs, runbooks, specs, commit messages, moduledocs, comments, PR text, or chat replies; also /unslop FILE.
---

Strip the patterns that mark text as machine-written. Meaning stays, voice tightens.

## Banned words

delve, crucial, pivotal, testament, tapestry, landscape, interplay, intricate, vibrant, underscore, enduring, additionally, leverage, robust, seamless, comprehensive, holistic, foster, empower, journey, elevate, supercharge

## Banned constructions

- "serves as" / "stands as" / "acts as" -> "is"
- "not just X, but Y"
- forced triads where two concrete points are enough
- empty gerund tails, such as "ensuring reliability" or "highlighting the importance"
- hedge stacks, such as "could potentially"
- "It's important to note", "Here's where it gets interesting", "the kicker"
- vague authority, such as "experts believe" or "many argue"
- filler: "in order to" -> "to"; "the fact that" -> drop it

## Banned formatting

- bold sprinkled on nouns; bold only as a scan anchor
- decorative emoji
- em-dash chains; use a period when a period works
- a colon splice where a period works

## Banned tone

- "Great question!", "Hope this helps!", "Let's dive in"
- preamble before the answer, recap after it
- "In conclusion", "Overall"

## House calibration

Deterministic booking logic Hex library. Keep booking, availability, boundary, interval, constraint, conflict, deterministic, Livebook, HexDocs, and host-application terms exact. Avoid product-platform claims.

Code, commands, error output, file paths, identifiers, dates, and numbers stay verbatim. Never paraphrase a measured result or a contract boundary.

Domain registers compose on top of this skill. If another local skill governs Elixir docs, specs, legal text, research prose, or product copy, obey that skill's terminology and wrapping rules while applying this cleanup pass.

## Self-audit

Before finishing, reread once and ask: what here is obviously AI-generated? Fix it.

With a file argument: read $ARGUMENTS, rewrite it under these rules, preserve technical claims and code blocks exactly, and report what changed in two or three lines.
