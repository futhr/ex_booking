---
ex_booking:
  id: "SP.07"
  title: "Validation"
  domain: booking
  status: normative
  priority: high
  created: "2026-07-08"
  updated: "2026-09-06"
  tags: ["tests", "quality-gates", "coverage", "properties"]
  depends_on: ["SP.03"]
---

# SP.07 — Validation

This spec describes the validation setup for this repo. It is not a roadmap;
roadmap state lives only in `docs/tasks/booking-tasks.md`.

## Test Layout

```text
test/ex_booking_test.exs              facade behavior and lifecycle examples
test/ex_booking/*_test.exs            module-level example tests
test/support/builders.ex              plain struct builders
test/support/generators.ex            StreamData generators
test/support/dst_fixtures.ex          pinned DST transition corpus
```

## Required Test Styles

- **Doctests** for public examples on public modules/functions.
- **Example tests** for error vocabulary, lifecycle branches, and edge cases.
- **Property tests** for interval algebra and slotting invariants.
- **DST fixtures** for timezone-sensitive behavior in `Europe/Stockholm` and
  `America/New_York`.
- **Determinism checks** for stable ordering and total tie-breaks.
- **Malformed-input checks** proving invalid request identity/duration,
  incomplete or reversed horizons, invalid strategies, non-positive weights,
  inconsistent holds, malformed nested availability facts, lifecycle policies,
  fairness values, scorer results, and non-UTC/type-invalid intervals return the
  SP.02 tagged errors without raising.
- **Requested-slot containment checks** proving validation requires the whole
  slot to fit expanded offerability, including overrides and blackouts, before
  applying current busy and policy inputs.
- **Standards fixtures** proving iCalendar `FBTYPE=FREE` periods do not become
  busy while absent, recognized busy, and unknown `FBTYPE` values do.

## Required Properties

The property suite must cover:

- `Interval.overlaps?/2` symmetry;
- `Interval.new/3` UTC normalization and `Interval.validate/1` acceptance of
  generated valid UTC intervals;
- `Interval.subtract/2` containment and disjointness;
- `Interval.merge/1` idempotence and normal form;
- `Interval.clip/2` containment;
- availability/validation buffer equivalence;
- slot starts fit inside free intervals and follow the grid step.

## Quality Gates

`mix check --no-retry` is the repo-level gate. It runs or wraps:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix deps.audit
mix hex.audit
mix dialyzer
mix doctor
mix docs
mix test --cover
mix verify.package
```

Coverage must remain at or above 95% line coverage with `test/support` excluded.
`mix doctor` must keep 100% moduledoc and public spec coverage.

## Change Rule

Any change that touches behavior must update the matching spec, task checklist,
and tests in the same commit. Do not add dependencies or integration behavior to
satisfy tests; keep the kernel pure and push effects to consumers.

## Registry advisory gate

Both `mix deps.audit` and `mix hex.audit` must pass. The latter checks current Hex
registry advisories and fails when vulnerable or retired locked packages are found.
The release workflow inherits both checks through `mix check --no-retry`.

## Development dependency maintenance

The September 2026 maintenance baseline uses ExDoc 0.40.4 and Req 0.7.4. ExDoc fixes documentation output and navigation; Req fixes query-parameter and redirect handling. These are development-only lockfile updates and do not expand the runtime dependency surface. Release notes: [ExDoc](https://github.com/elixir-lang/ex_doc/releases/tag/v0.40.4), [Req](https://github.com/wojtekmach/req/releases/tag/v0.7.4).

## Pinned CI action maintenance

All checkout and cache action references use full commit pins for checkout v7.0.1 and cache v6.1.0. Checkout v7 restricts unsafe privileged fork-PR checkout; our push and pull_request triggers remain supported. Cache v6 uses the Node 24 ESM runtime, supported by GitHub-hosted Ubuntu runners. Keep credential persistence disabled. Release notes: [checkout](https://github.com/actions/checkout/releases/tag/v7.0.1), [cache](https://github.com/actions/cache/releases/tag/v6.1.0). Local gates validate repository behavior; hosted workflow execution remains a CI responsibility.

## Behavioral property coverage

Generators include arbitrary seconds and microseconds. Clock-grid properties produce nonempty multi-day results and inspect every slot without conditional skips. Assignment properties cover proportional load, permutation invariance, unbounded counters, and missing fairness. Weekly recurrence is checked against an independently enumerated calendar-day reference including Monday anchoring and absolute COUNT before horizon filtering. Daily recurrence cardinality and wall time are checked across both Stockholm and New York DST gaps. Lead-time properties exercise every generated positive subsecond deficit and its exact accepting boundary. Normalized subtraction completeness and pool peak capacity are covered alongside their fixes (A16/A17).

## Archive and notebook verification

`mix verify.package`, included in `mix check --no-retry` and every CI runtime-matrix job, builds and extracts an actual Hex archive into temporary directories. A fresh production consumer resolves only the runtime dependencies, compiles and exercises timezone-aware availability and decisions, and verifies the application dependency list and absence of an application callback. Packaged notebooks are required. Their actual setup cells run in fresh Elixir processes before every example and saved output is checked. Identical setup sources may share a process. The archive/local-source setup branch is executed; the released-version branch is pin-checked and its registry contents remain release-specific hosted evidence. Temporary artifacts are removed on success or failure.

## Performance and maintenance evidence

A full benchmark run uses 2 seconds of warmup, 5 seconds of timing, and 1 second of memory measurement per scenario. The tracked report is produced only by full runs. Smoke output is ignored and separate. Scenarios must return successful nonempty results before timing; the JSCalendar Group fixture uses the standard entries array. Recorded input construction is part of workload cost. Weekly CI checks security independently of new commits. Mix and GitHub Actions version updates are maintained manually and require the full gate. Hosted workflow execution, registry publication and release provenance cannot be certified by local gates.

## Audit regression traceability

The logical findings A02–A17 each have named regressions tagged with their
audit ID. Run the whole set with `mix test --only audit_finding`, or one finding
with, for example, `mix test --only audit_finding:A10`. Tags select existing
examples and properties as well as public-facade boundary checks; every listed
regression also runs in the ordinary suite and `mix check`.

| Finding and contract | Regression tests |
|---|---|
| **A02** — Duplicate resource identities cannot multiply capacity or repeat assignment. | [assignment rejects duplicate identities before selection](../../test/ex_booking/assignment_test.exs#L230)<br>[duplicate resource identity cannot multiply pool capacity](../../test/ex_booking/availability_input_validation_test.exs#L273)<br>[duplicate resources are rejected by decision and reschedule entry points](../../test/ex_booking_test.exs#L829) |
| **A03** — Collective preferences retain required participants on both rejection and acceptance. | [collective preferences cannot remove a required busy resource](../../test/ex_booking/availability_test.exs#L441)<br>[accepted collective decisions keep every participant despite preferences](../../test/ex_booking_test.exs#L846) |
| **A04** — Sparse weekly recurrences stop at the horizon, with/without COUNT and BYDAY. | [large weekly intervals terminate within a one-day horizon](../../test/ex_booking/rrule_test.exs#L219)<br>[sparse weekly rules with and without BYDAY stop at empty horizons without COUNT](../../test/ex_booking/rrule_test.exs#L343) |
| **A05** — Unsupported recurrence is rejected before free/cancelled filtering, including Group entries. | [rejects recurrence additions and exclusions even on a free base event](../../test/ex_booking/jscalendar_test.exs#L289)<br>[cancelled events and nested groups cannot hide unsupported recurrence](../../test/ex_booking/jscalendar_test.exs#L309) |
| **A06** — Alternatives revalidate under preferred IDs in one/pool/collective modes and rescheduling. | [alternatives retain preferred resource constraints](../../test/ex_booking_test.exs#L751)<br>[pool and collective alternatives revalidate for decisions and reschedules](../../test/ex_booking_test.exs#L866) |
| **A07** — Weekly INTERVAL uses Monday anchors and COUNT is applied before horizon filtering. | [biweekly BYDAY is anchored to Monday rather than DTSTART weekday](../../test/ex_booking/rrule_test.exs#L237)<br>[weekly expansion matches a calendar-day reference with absolute COUNT](../../test/ex_booking/rrule_test.exs#L284) |
| **A08** — COUNT/UNTIL conflict is rejected; DST gaps in both zones do not consume COUNT. | [skips a Stockholm gap without consuming COUNT](../../test/ex_booking/rrule_test.exs#L187)<br>[COUNT and UNTIL cannot be combined](../../test/ex_booking/rrule_test.exs#L252)<br>[New York spring gap does not consume COUNT](../../test/ex_booking/rrule_test.exs#L267)<br>[daily COUNT counts valid local times across both spring DST gaps](../../test/ex_booking/rrule_test.exs#L316) |
| **A09** — Every positive subsecond lead-time deficit rejects while the exact boundary accepts. | [lead time rejects subsecond shortfalls and allows the exact boundary](../../test/ex_booking/policy_test.exs#L184)<br>[every positive subsecond lead-time deficit rejects, while the boundary accepts](../../test/ex_booking/policy_test.exs#L199) |
| **A10** — Slots/availability/holds compare instants; alternatives retain fractional distance; fall-back instants remain distinct. | [availability deduplicates equivalent timestamp precision in one and pool modes](../../test/ex_booking/availability_test.exs#L530)<br>[equal instants deduplicate regardless of display precision](../../test/ex_booking/slotting_test.exs#L171)<br>[deduplication preserves distinct fall-back instants in both DST zones](../../test/ex_booking/slotting_test.exs#L182)<br>[holds compare UTC instants rather than timestamp display precision](../../test/ex_booking_test.exs#L780)<br>[nearest alternatives distinguish fractional-second distances](../../test/ex_booking_test.exs#L909) |
| **A11** — Missing fairness ranks explicitly behind arbitrarily large supplied values. | [missing fairness ranks after any supplied magnitude](../../test/ex_booking/assignment_test.exs#L236)<br>[a missing counter ranks behind every supplied nonnegative count](../../test/ex_booking/assignment_test.exs#L350) |
| **A12** — Weighted assignment handles huge integers/tiny floats; all recency strategies retain microseconds. | [weighted ranking accepts extreme positive numeric weights](../../test/ex_booking/assignment_test.exs#L275)<br>[assignment retains microseconds in recency comparisons](../../test/ex_booking/assignment_test.exs#L301)<br>[weighted winners minimize proportional load regardless of input order](../../test/ex_booking/assignment_test.exs#L333) |
| **A13** — Public assignment/availability/lifecycle paths reject malformed options, capacities, IDs and context. | [standalone assignment validates participant options and resource capacity](../../test/ex_booking/assignment_test.exs#L318)<br>[standalone availability rejects malformed options and nil preferred ids](../../test/ex_booking/availability_input_validation_test.exs#L286)<br>[lifecycle options reject malformed lists and empty identities](../../test/ex_booking_test.exs#L809) |
| **A14** — Closed dates remove inbound overnight time at both spring and autumn DST transitions. | [closed dates suppress overnight spill across spring and autumn DST transitions](../../test/ex_booking/schedule_test.exs#L182) |
| **A15** — Empty FREEBUSY periods reject, including FREE-marked periods and empty list elements. | [empty FREEBUSY periods are malformed even when marked FREE](../../test/ex_booking/icalendar_test.exs#L143) |
| **A16** — Subtraction returns the complete normalized set difference and preserves elapsed DST time. | [set subtraction equals the normalized reference and retains all free time](../../test/ex_booking/interval_test.exs#L261)<br>[set subtraction normalizes overlapping minuends](../../test/ex_booking/interval_test.exs#L273)<br>[subtraction preserves elapsed time across both spring DST gaps](../../test/ex_booking/interval_test.exs#L279) |
| **A17** — Pool accounting uses simultaneous sums, handles adjacency, buffers and DST, and keeps sequential consumption separate. | [consecutive reservations do not consume seats simultaneously](../../test/ex_booking/availability_test.exs#L456)<br>[pool capacity remains available across both spring gaps](../../test/ex_booking/availability_test.exs#L492)<br>[pool capacity sums simultaneous consumption and clips buffered boundaries](../../test/ex_booking/availability_test.exs#L553) |

Maintenance findings A01, A18 and A19 are checked through dependency/security
audits, docs compilation and workflow linting. A20 is a behavior-preserving
refactor guarded by the A02, A11–A13 regressions and the full suite. A21 describes
property-suite improvements; the properties above and the ordinary algebra/grid
properties execute those contracts. A22 has archive-consumer and actual notebook
setup/example verification in `mix verify.package`; benchmark preconditions and
separate smoke/full output checks cover its executable harness changes. These
maintenance checks do not replace the logical regressions.

### Discrimination checks recorded September 6, 2026

The unmodified source passed the tagged suite. An isolated source copy was then
used to reintroduce faults one at a time and run
`mix test --only audit_finding:AXX --seed 0`. The original pre-A04 recurrence
module was used for the unbounded-traversal case. Other probes made focused
changes to the current implementation. The working repository's runtime source
was never mutated.

All **28 behavior-changing probes** were detected by the tagged regressions,
covering all **16 logical findings**. The normal tagged run passed **40 tests
and properties**.

| Finding | Injected faults detected |
|---|---|
| A02 | allow duplicate resource identities |
| A03 | filter collective participants |
| A04 | restore the original unbounded weekly traversal |
| A05 | ignore exclusion and override recurrence; filter cancelled events before recurrence |
| A06 | drop preferred resource constraints from alternatives; filter collective alternatives by preferences |
| A07 | anchor weekly intervals to DTSTART weekday |
| A08 | allow COUNT together with UNTIL; snap and count nonexistent local times |
| A09 | truncate lead time to whole seconds |
| A10 | deduplicate slot structs instead of instants; deduplicate availability structs instead of instants; compare holds by struct equality; truncate alternative distance to seconds |
| A11 | rank missing counts with finite sentinels; rank missing weighted counts with a finite sentinel |
| A12 | divide weighted loads using floating point; truncate assignment recency to seconds |
| A13 | silently keep the first duplicate option; accept empty lifecycle identities; accept nil preferred resource ids |
| A14 | let overnight availability spill into closed days |
| A15 | silently discard empty FREEBUSY tokens |
| A16 | leave overlapping minuends unnormalized |
| A17 | sum sequential reservations as if concurrent; use the largest reservation instead of concurrent sum; ignore reservation buffers |


This checks specific historical failure modes and nearby boundary errors; it is
not exhaustive mutation analysis. One preliminary removal of the duplicate-key
check still rejected duplicates through NimbleOptions and was therefore an
equivalent rejection, not a missing logical regression. The corresponding
behavior-changing probe silently retained the first duplicate value; the
regressions reject that behavior. No compile/harness failure counts as detecting
a fault. New cases were already green because the behavior was implemented;
the fault injections establish that their assertions distinguish broken behavior.
