---
name: verify
description: Verify the affected repository surface before handoff, an authorized commit, or a completion or release-readiness claim. Select checks for kernel code, public APIs, notebooks, packaging, or agent guidance, and report actual outcomes plus failed, blocked, skipped, and hosted-only proof.
user-invocable: false
---

# Verify delivery evidence

Inputs: the final diff, requested scope, available tools, and earlier observed
results. Output: an evidence-scoped handoff with commands actually run, outcomes,
and material limitations. Keep validation output in chat unless an artifact is
explicitly part of the requested deliverable.

1. Inspect the final Git state and diff for unintended edits and generated
   leftovers. Run `git diff --check`; inspect staged changes too when present.
2. For application changes, select focused checks from
   [SP.07](../../../docs/specs/SP.07-validation.md), then run
   `mix check --no-retry` using the existing environment. Inspect every component
   result; a skipped component is not a pass. The aggregate uses `.check.exs`,
   including dependency/security, types, documentation, coverage, archive-consumer,
   and notebook checks. Do not run every component twice after a successful gate.
3. For changed public/package surfaces, inspect the actual archive consumer and
   notebook evidence. Use `mix verify.package --matrix` when dependency
   compatibility claims require the additional supported dependency combinations.
   Do not infer real downstream or published-registry behavior from local checks.
4. For guidance changes, parse skill frontmatter and check directory/name matches,
   descriptions and invocation policy. Resolve file references from each skill
   directory and inspect their actual targets. Check Git tracking/ignore rules,
   individual local discovery links, absence of duplicate aliases, and preservation
   of local settings. Static metadata checks do not prove model selection.
5. If a failure is actionable within scope, fix it and rerun affected checks.
   If tooling, dependencies, network, or hosted access is unavailable, report the
   exact blocker and the proof that did not run. Never describe a declaration or
   planned command as a successful test.

Preserve the validation boundary: passing focused assertions, full local gates,
hosted CI, and actual consumer execution support different claims. Use fresh
results after relevant edits, and state any limitation with the authorized delivery.
