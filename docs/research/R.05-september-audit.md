---
ex_booking:
  id: "R.05"
  topic: "September 2026 correctness and maintenance audit"
  category: research
  status: adopted
  created: "2026-09-05"
  updated: "2026-09-05"
  decision: "Adopt the audited correctness fixes, stable maintenance updates, and executable archive verification while retaining the pure kernel and existing runtime dependencies."
  tags: ["audit", "correctness", "security", "performance", "packaging"]
---

# R.05 — September 2026 audit

## Executive Summary

The audit found correctness defects in identity handling, collective eligibility,
recurrence, precise time comparison, fairness, interval subtraction and pooled
capacity. It also found gaps between maintenance claims and executable evidence.
Targeted regressions and the full quality gate accompany the fixes. The complete
finding ledger and completion state are in the [task list](../tasks/booking-tasks.md#september-2026-audit-remediation).

The existing architecture remains appropriate: pure functions, explicit caller
facts, two runtime dependencies, and consumer-owned effects. “State of the art”
is an aspiration rather than a certifiable property. This audit establishes
specific invariants and repeatable evidence; it does not establish exhaustive
protocol support, universal optimality, or production latency guarantees.

## Research Question

Which changes improve correctness, bounded execution, dependency maintenance and
Hex-consumer confidence without expanding the kernel's responsibilities?

## Methodology

The close-reading set included `lib/`, tests and generators, Mix manifests,
release and CI workflows, notebook evaluation, benchmark scenarios, normative
specifications and the existing research corpus. Screening prioritized observable
misbehavior, hidden unbounded work, contradictory documentation and unsupported
claims over cosmetic rewrites. No private consumer repository was required; a
fresh consumer of the extracted archive supplies an explicit integration check.

Dependency decisions use current stable releases and their upstream changelogs,
not release age alone. Mint advisories were reconciled with both audit tools:
the existing dependency audit passed while the Hex registry reported affected
Mint 1.9.3. ExDoc's installed 0.40.4 changelog was also read because a cached web
view still stopped at 0.40.3. Req's tagged 0.7.4 release was used instead of
inferring stability from its next prerelease development branch.

Behavioral changes were checked against focused regressions, reference-based
properties, DST fixtures and the full gate. Refactoring retained these behavioral
checks while removing duplicate field definitions and unreachable branches.
The performance report uses a full Benchee run: 2 seconds warmup, 5 seconds timing
and 1 second memory measurement per workload. Input construction is included.
This is a current baseline, not a controlled before/after speedup experiment.

## Findings

RFC 5545 requires nonexistent local recurrence times to be ignored without
consuming COUNT, and forbids combining COUNT with UNTIL. Weekly intervals need a
consistent week anchor. The former sequential-walk recommendation in R.04 did
not cover extremely large weekly INTERVAL values; those exposed an unbounded
search even for short query horizons. That evidence supersedes the old decision.

JSCalendar recurrence directives cannot be silently discarded during busy-time
normalization. Rejecting unsupported recurrence is preferable to reporting
incomplete availability facts. No new recurrence dependency was needed to
implement the deliberately supported subset.

The Mint 1.10.0 security release, ExDoc 0.40.4 documentation fixes and Req 0.7.4
request fixes fit the existing dependency constraints. Runtime dependencies remain
`tz` and `nimble_options`. Checkout/cache updates retain full commit pins and
credential restrictions. Weekly CI and update proposals make maintenance
repeatable; version updates still require review and verification.

The notebook test skipped setup while claiming every cell ran. The archive also
omitted notebook sources referenced by its documentation configuration. Fresh
archive verification now exercises the production consumer and actual local-source
notebook setup branch. Registry-version setup remains release-specific evidence;
a version-pin assertion alone is not represented as execution of that branch.

The benchmark's JSCalendar Group used an invalid entries map, so it measured
rejection instead of parsing 500 events. Scenario preconditions now reject failed
or empty results, that fixture is an array, and smoke output cannot replace the
tracked full report. In this run, subtraction of 1,000 busy intervals averaged
1.42 ms. The 100-resource, four-week pool workload averaged 311.31 ms and allocated
664.15 MB cumulatively in the measured process. Benchee allocation totals include
garbage-collected memory and are not peak resident memory. Dense pool search
remains the most expensive measured scenario; consumer latency budgets and actual
workload distributions should guide further optimization.

## Comparative Analysis

| Choice | Evidence and tradeoff | Decision |
|---|---|---|
| Replace the kernel or add a recurrence dependency | Larger semantic and dependency surface without a demonstrated need | Retain the architecture |
| Keep sequential weekly traversal | R.04's ordinary intervals missed extreme INTERVAL behavior | Bound traversal and jump active weeks |
| Treat setup pins and smoke timings as proof | Neither executes the claimed installation/performance contract | Add archive checks and full measurements |
| Update every dependency to development HEAD | Recency does not establish released compatibility | Use supported stable releases |
| Rewrite large modules for appearance | Broad churn would obscure the demonstrated defects | Consolidate duplicated validation and remove dead branches |

## Recommendation

**Decision: adopted.** The semantic owners are the normative specifications and
the modules implementing them. The falsifiers are a failing regression,
reference-equivalence property, advisory audit, archive-consumer check or required
quality gate. No source was copied or paraphrased from copyleft projects.

## Impact on ExBooking

Specifications SP.01–SP.07 and the [canonical task ledger](../tasks/booking-tasks.md)
record the accepted contracts. Changes are committed separately by finding.
The changelog records user-visible recurrence and malformed-input differences;
publication requires a deliberate release decision. No version, tag, repository
visibility or hosted release was changed during remediation.

Local evidence includes a passing `mix check --no-retry`, 70 doctests,
25 properties, 251 example tests, 96.6% line coverage, and clean actionlint output.
Tests and archive/notebook verification also passed in fresh copies on Elixir
1.19.4 / OTP 28.5 and Elixir 1.20.2 / OTP 29.0.4. The 1.18.4 / OTP 28.5 gate
includes the same archive verification. All locked packages were current under
`mix hex.outdated --all` on September 5.

Fresh builds exposed upstream compiler notices in ExCoveralls (including an
optional CAStore reference), doctest_formatter, ex_check, doctor and tz on newer
Elixir, plus a local linker search-path warning in file_system. These notices
did not fail the tests or production-consumer checks; no warnings were suppressed
and no dependencies were forked or added to hide them. Hosted CI,
Dependabot execution, registry publication and provenance attestation remain
hosted checks; local success does not imply those services have run.

## Sources

- [RFC 5545 §3.3.10](https://www.rfc-editor.org/rfc/rfc5545.html#section-3.3.10), recurrence rules, COUNT and invalid local times.
- [RFC 8984](https://www.rfc-editor.org/rfc/rfc8984.html), JSCalendar Event and Group semantics.
- [Mint v1.10.0](https://github.com/elixir-mint/mint/releases/tag/v1.10.0), September 4, 2026; fixes the advisories reported against 1.9.3.
- [ExDoc changelog](https://github.com/elixir-lang/ex_doc/blob/v0.40.4/CHANGELOG.md), v0.40.4, September 3, 2026; corroborated by the installed package changelog.
- [Req v0.7.4](https://github.com/wojtekmach/req/releases/tag/v0.7.4), August 26, 2026.
- [Checkout v7.0.1](https://github.com/actions/checkout/releases/tag/v7.0.1) and [cache v6.1.0](https://github.com/actions/cache/releases/tag/v6.1.0), stable action releases checked September 5, 2026.
- [Dependabot configuration reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference), checked September 5, 2026.
- [Benchee memory measurement](https://github.com/bencheeorg/benchee#memory-measurements), corroborated by the installed 1.5.1 README.
- [Full measured report](../../bench/output/benchmarks.md), macOS, Apple M5 Pro, Elixir 1.18.4 / OTP 28.5.
