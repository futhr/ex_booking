---
ex_booking:
  id: "R.06"
  topic: "Evidence-driven production hardening"
  category: research
  status: adopted
  created: "2026-09-11"
  updated: "2026-09-11"
  decision: "Retain the pure kernel and public facade; correct demonstrated boundary defects, remove repeated Group merges, and verify extracted archives across selected runtime and dependency combinations."
  tags: ["audit", "correctness", "security", "performance", "packaging"]
---

# R.06 — Production hardening

## Decision and scope

The September 11 audit started from `8838d0c` with a clean working tree. The
initial audit was read-only and its full findings were presented before edits.
Specifications and acceptance criteria preceded each implementation batch.
Later reproduction of an unresolved recurrence timezone and execution of the
README example produced two additional findings, disclosed before their fixes.

The changes harden temporal validation, calendar import, recurrence parsing,
hold preflight and consumer verification. They retain the pure kernel, existing
facade signatures, native data representation and two runtime dependencies.
Invalid inputs that previously raised, disappeared, or produced out-of-range
endpoints now return checked errors. Valid quoted ICS parameters are accepted.
Completion state belongs to the [task list](../tasks/booking-tasks.md#september-11-production-hardening).

## Method and support surface

The audit read `AGENTS.md`, `CLAUDE.md`, the applicable `.claude/` standards and
skills, README, contributing guidance, research usage rules, all eight specs,
implementation tasks, library modules, tests and generators, notebooks, Mix
declarations and lock, quality configuration, package scripts, and CI/release
workflows. There is no separate `usage-rules.md` in this checkout. Claims were
compared with runtime probes and regressions rather than inferred from coverage.

`mix.exs` declares Elixir `~> 1.18`, `tz ~> 0.28`, and
`nimble_options ~> 1.1`. The CI pairs are Elixir 1.18/OTP 28, 1.19/OTP 28,
and 1.20/OTP 29. Mint and CAStore are optional timezone dependencies; neither
HTTP nor a JSON library is required by the booking kernel. Development tools
remain development/test dependencies. No declaration or lock changed here.

Protocol judgments used the primary sources: [RFC 5545 §3.2.9 and §3.3.6](https://www.rfc-editor.org/rfc/rfc5545.html)
for FBTYPE cardinality and duration syntax, and
[RFC 8984 §1.4 and §4.3](https://www.rfc-editor.org/rfc/rfc8984.html) for JSCalendar
types and time semantics. [Elixir 1.18 DateTime documentation](https://elixir.hexdocs.pm/1.18.4/DateTime.html)
informed checked conversion and arithmetic. No third-party product code was copied.

## Confirmed findings and resolutions

Locations below identify the original defect at `8838d0c`; regression links
refer to the resulting checkout. Severity reflects the demonstrated impact,
not an assertion of remote exploitability.

| Severity | Exact original location | Reproduction or concrete evidence | Impact and smallest appropriate fix | Resolution |
|---|---|---|---|---|
| High | `lib/ex_booking/icalendar.ex:72–117` | `FREEBUSY;FBTYPE=FREE;FBTYPE=BUSY:20260713T090000Z/PT30M` returned `{:ok, []}`. A quoted `X-URL="https://example.test/a;b,c"` was split at its colon. | Ambiguous input could remove busy time; valid extension parameters were misparsed. Scan delimiters outside quotes and reject repeated FBTYPE, including case aliases. | `247d6f8`; [ICS regressions](../../test/ex_booking/icalendar_test.exs). |
| High | `lib/ex_booking/jscalendar.ex:220–237`; `lib/ex_booking/icalendar.ex:205` | `PT99999999999999999999S` produced an endpoint in year 3168873852707. `P99999999999999999D` remained in calendar arithmetic until the isolated probe was terminated. | Small inputs could cause excessive computation or successful unusable calendar endpoints. Compare the parsed duration against the remaining four-digit calendar range before arithmetic; preserve the last representable second/microsecond. | `247d6f8`, `7bedc94`; duration-boundary tests for both importers. |
| Medium | `lib/ex_booking/interval.ex:52–95`, `schedule.ex:170–196`, `options.ex:69–86`, `resource.ex:106`, `availability.ex:614`, `lib/ex_booking.ex:734`; RRULE argument validation | A hand-built DateTime with month 13 raised; a Time with hour 25 passed schedule validation and its window disappeared; malformed `now` passed an empty-resource search. | Struct tags alone did not establish valid calendar fields. Share field validation before arithmetic and apply it to nested dates/times, horizons, fairness, holds and recurrence. | `454d16c`; seven [temporal regressions](../../test/ex_booking/temporal_validation_test.exs) failed before the fix and passed after it. |
| Medium | `lib/ex_booking/jscalendar.ex:52–61,133–181`; `lib/ex_booking/icalendar.ex:41–74` | Atom-keyed `:duration` was ignored, defaulting an otherwise string-keyed Event to zero duration. `"PT30M\n"` was accepted. ICS `<<255>>` returned `{:ok, []}`. | Input representation mistakes silently lost busy time or bypassed token validation. Require plain JSCalendar objects with UTF-8 string keys, anchor complete tokens, and reject invalid ICS encoding. | `247d6f8`, `7bedc94`; alias, encoding and trailing-token regressions. |
| Medium | `lib/ex_booking/jscalendar.ex:68–79` | Each nested Group recursively merged the complete child result again. The controlled 800-event run allocated 132.44 MB and took a 66.15 ms median. | Nested Groups incurred quadratic repeated copying. Traverse an explicit work stack, accumulate events and merge once. | `7bedc94`; nesting-union property, first-error order test and measured scaling below. |
| Medium | `lib/ex_booking.ex:264–270,647–697` | An empty hold id with no offerable resource returned a `:needs_routing` decision instead of an invalid-hold error. | Expected validation depended on unrelated availability. Check supplied hold shape before availability; retain assignment-dependent matching after selection. | `70fe187`; malformed id/slot/resource ids/expiry tested with empty and unofferable resources; absent hold behavior retained. |
| Low | `lib/ex_booking/rrule.ex:108–112,173–178` | `FREQ=DAILY;` and `FREQ=WEEKLY;BYDAY=MO,` succeeded because splitting discarded empty elements. | Malformed rules were normalized silently. Preserve empty tokens and return existing `:part`/`:byday` errors; retain the empty-rule `:freq` error. | `b642159`; [RRULE regressions](../../test/ex_booking/rrule_test.exs). |
| Low | `docs/specs/SP.00-overview.md:66–68`, `SP.02-public-api.md:79,202`, `SP.05-lifecycle-and-events.md:138` | Specs promised all opaque metadata round-tripped and decisions embedded everything in force; actual decisions omit request metadata, rules, policies and fairness state. Duration pseudocode used whole seconds; the cancellation spec omitted its error return. | Consumers could rely on nonexistent replay data or inaccurate precision/error guidance. Describe actual propagation and microsecond validation, correct the typespec example, and state snapshot/transaction ownership. | `74ba37d`; type-strict routing-context behavior test plus corrected contracts. |
| Medium | `lib/ex_booking/rrule.ex:265–268` | A structurally valid DTSTART whose zone was `Missing/Zone` raised from `DateTime.shift_zone!` while deriving the local horizon. | Unknown caller-supplied zones escaped the tagged-error boundary. Check conversion, return the existing `:arguments` error, and reuse the converted horizon. | `b642159`; unresolved-zone regression failed before the fix. |
| Low | `README.md:108–109` | Executing the actual quick start emitted a compiler warning because `_payload` occurred twice in one match. | The example was not diagnostic-free. Rename both bindings to `payload`, preserving the intended equality match, and execute the extracted README in each archive consumer with diagnostics asserted empty. | Packaging verification batch; final example passed on all three runtime pairs. |

The individual regression groups were run before implementation to establish
failure, then after the corresponding fix. The three new JSCalendar defect
tests cover keys, complete tokens and duration bounds; additional behavior tests
cover first-error ordering, four-digit UTC conversion boundaries and spring/fall
calendar-day durations in Stockholm and New York. No regression assertion or
coverage threshold was weakened to obtain green results.

## Tradeoffs, hypotheses and excluded work

Clock alignment keeps one constant step phase from the initial UTC midnight.
For a seven-minute step, a later day's first candidate can be 00:02. The former
property generated only divisors of 1440 and did not establish behavior for
other valid steps. A new property samples steps 1–2000 across a four-day window;
the existing property remains. Resetting phase at every midnight would be a
behavior decision, so this audit documented and preserved the current contract.

Dense resource pools and daily recurrence starting far before the horizon remain
potential profiling targets, not newly established defects. No speculative
index, cache, dependency, abstraction or provider adapter was added. The measured
recurrence workload below has a nearby DTSTART and does not settle distant-start
cost. Parsing still costs resources proportional to caller input; there is no
universal byte, nesting, event-count or horizon budget imposed by this kernel.
Consumers must budget input size and work appropriate to their service.

There is no production persistence, filesystem staging, lock, ETS table,
publication transaction, background process or raw JSON decoder in `lib/`.
Consequently an error-after-publication, rollback, stale-file deletion or crash
recovery guarantee cannot be demonstrated for this package. Consumers must
revalidate a coherent snapshot and commit reservation changes, including removal
of the old reservation during rescheduling, atomically. Returned intents alone
do not provide rollback or exactly-once delivery. Local packaging scripts create
and remove their own temporary directories; they do not publish a release.

The existing resource/request/hold identity checks were reviewed alongside
duplicate-id, participant and lifecycle tests. These are consistency checks,
not authentication or a complete provenance envelope. Decisions do not identify
all inputs or timezone/scorer versions needed for replay. No signature,
serialization format or generation identifier was invented. No portable
filesystem check is claimed to protect against hostile concurrent writers.

JSCalendar consumes already-decoded maps. Duplicate raw JSON keys may have been
lost before the kernel sees them and must be rejected by the consumer's decoder.
The kernel now rejects atom/string aliases in relevant objects and handles native
values directly, with no encode/decode pass or atom creation from input. A new
`===` regression preserves integer `1`, float `1.0`, `false`, `nil` and arrays in
routing context through scoring, events and emit intents. Arbitrary unrelated
metadata is not recursively treated as a JSON serialization schema.

Calendar, timezone-database and scorer implementations remain trusted extension
code. Field validation does not authenticate supplied timezone offsets against
history. Checked expected failures do not broadly rescue programming errors in
callbacks. Exhaustive malformed terms, hostile callback implementations, and
arbitrarily large integer strings were not proved safe by this audit.

## Executable verification

Baseline `mix test --seed 0`: **70 doctests, 25 properties, 259 tests, zero
failures**. Baseline `mix deps.audit`, `mix hex.audit`, and extracted fresh
production consumer plus six notebooks passed. This baseline did not imply the
later malformed-input probes were covered.

Each implementation commit passed `mix check --no-retry` on
Elixir 1.18.4/OTP 28.5.0.6 before commit. `--no-retry` forces the complete
configured pipeline rather than ex_check's previous-failures retry selection.

| Commit | Change | Doctests / properties / tests | Line coverage |
|---|---|---|---|
| `454d16c` | Validate temporal fields before arithmetic | 73 / 25 / 266 | 96.7% |
| `247d6f8` | Parse quoted ICS parameters and reject ambiguous FREEBUSY | 73 / 25 / 270 | 96.9% |
| `7bedc94` | Validate JSCalendar and merge nested Groups once | 73 / 26 / 276 | 96.8% |
| `b642159` | Reject malformed RRULE parts and unresolved zones | 73 / 26 / 278 | 96.9% |
| `70fe187` | Validate holds before availability rejection | 73 / 26 / 279 | 97.1% |
| `74ba37d` | Clarify metadata, snapshots and clock alignment | 73 / 27 / 280 | 97.1% |

The final commit, `test(packaging): verify dependency matrices and executable examples`,
adds `mix verify.package --matrix`, diagnostic-free README execution, boundary
smoke checks, and the comparable benchmark fixture. Its final
`mix check --no-retry` passed all 12 applicable tools in 11 seconds: **73 doctests,
27 properties, 280 tests, zero failures; 97.1% line coverage**, seed 275684.
`git diff --check` and the independent format check also passed.

The unchanged gate requires compilation with warnings as errors, formatting,
strict Credo, dependency and Hex security audits, Dialyzer, Doctor, ExDoc,
coverage tests, and extracted-package verification. Doctor reported 100% doc,
moduledoc and spec coverage for each completed batch. Dialyzer reported zero
errors and zero skips. The automatically detected unused-dependency check also
ran; Gettext/Sobelow were inapplicable because those dependencies are absent.

| Runtime check | Source compile and tests | Extracted archive matrix | Notebook setup and examples |
|---|---|---|---|
| Elixir 1.18.4 / OTP 28.5.0.6 | Pass; 73 doctests, 27 properties, 280 tests | All four modes passed | All six passed |
| Elixir 1.19.6 / OTP 28.5.0.6 | Pass; same counts | All four modes passed | All six passed |
| Elixir 1.20.4 / OTP 29.0.4 | Pass; same counts, reported as 380 passed | All four modes passed | All six passed |

The 1.19/1.20 source trees, dependencies and build artifacts were isolated
temporary copies, tested with `mix test --seed 0`. The 1.18 source received the
complete gate above. Each matrix built the actual Hex tarball, extracted its
contents, and tested clean production consumers against that package directory:

| Mode, on each runtime | Resolved direct runtime dependencies | Optional dependency check |
|---|---|---|
| Repository lock copied into temporary consumer | tz 0.28.2; nimble_options 1.1.1 | Mint and CAStore absent |
| Fresh resolution | tz 0.28.2; nimble_options 1.1.1 | Mint and CAStore absent |
| Selected compatible minimum direct versions | tz 0.28.0; nimble_options 1.1.0 | Mint and CAStore absent |
| Optional integrations installed | tz 0.28.2; nimble_options 1.1.1 | Mint 1.10.0, CAStore 1.0.21; hpax 1.0.4 transitively |

All 12 consumers compiled and passed availability/decision/timezone examples,
the actual README quick start, and malformed-input boundary checks. Jason was
absent in every consumer; the application dependency list and absence of an
application callback were asserted. Notebook setup ran in fresh processes using
the extracted archive, with all six notebooks verified once per runtime matrix.
No dependency override or repository lock update was used. None of these
selected combinations was incompatible; this is not an exhaustive minimum
transitive-dependency or patch-version matrix.

`mix run scripts/regen_notebook_outputs.exs` reported all six notebooks unchanged.
No generated notebook output or tracked benchmark report was hand-edited.

### Warnings and unsuccessful checks encountered

The first Dialyzer invocation encountered an incompatible pre-existing local
PLT. The ignored PLT and hash were preserved outside the checkout, the PLT was
rebuilt with `mix dialyzer --plt`, and subsequent complete gates passed. No
Dialyzer suppression or flag change was used.

The initial optional-consumer assertion mistakenly checked the nonexistent
root module `Mint`; inspection of the installed dependency corrected the
harness to `Mint.HTTP`. The final matrix was rerun on all runtimes. Initial
README evaluation exposed the repeated underscored binding; every final
consumer asserts no diagnostics from that example.

Upstream/toolchain warnings were retained and are not claimed fixed:

- ExCoveralls references optional `CAStore.file_path/0` when CAStore is absent.
- Elixir 1.20 additionally reports unused requires and unreachable clauses in
  ExCoveralls, a conditional-type warning in DoctestFormatter, unreachable Doctor
  clauses, ex_check's deprecated `xref: [exclude: ...]` configuration, and unused
  requires in tz 0.28.0/0.28.2.
- Native dependency compilation on the isolated 1.19/1.20 lanes reported a local
  missing `/opt/homebrew/opt/openjdk@21/lib` linker search path.
- Rebar reported stale local cache material during early setup.

The consumer and library `mix compile --warnings-as-errors` commands passed;
Mix dependency compilation still printed the upstream warnings described above.
Dependencies were not changed or warnings suppressed to obtain that result.

## Comparable hot-path measurements

The checked-in [benchmark fixture](../../bench/hardening.exs) constructs all
inputs before timed work and verifies successful nonempty results. Measurements
below used the original `8838d0c` library and the library at `74ba37d`, compiled
separately with the same locked dependencies and runtime. A Mix runner loaded
each revision's BEAM files explicitly and asserted consolidated protocols before
running the identical fixture. Baseline and changed runs were sequential, with
no concurrent build/test/benchmark workload.

Environment: macOS, Apple M5 Pro, 18 available cores, 48 GB RAM; Elixir 1.18.4,
OTP 28.5.0.6 with JIT, Benchee 1.5.1; one worker, 1 second warmup, 2 seconds
timing and 1 second memory measurement per scenario. Benchee's reported MB
figures below measure cumulative allocation by the measured process, **not peak
resident memory**. Preliminary unconsolidated runs were excluded from this table.

| Prebuilt workload | Before median | After median | Before allocation | After allocation |
|---|---:|---:|---:|---:|
| Nested Group, 100 events | 1.38 ms | 0.49 ms | 2.40 MB | 0.49 MB |
| Nested Group, 400 events | 16.89 ms | 1.97 ms | 33.87 MB | 1.97 MB |
| Nested Group, 800 events | 66.15 ms | 3.92 ms | 132.44 MB | 3.94 MB |
| Flat Group, 500 events | 2.19 ms | 2.39 ms | 2.03 MB | 2.38 MB |
| ICS, 500 periods | 4.27 ms | 4.30 ms | 4.04 MB | 4.32 MB |
| 1,000 interval constructors | 0.20 ms | 0.30 ms | 0.43 MB | 0.59 MB |
| 500 daily occurrences | 0.63 ms | 0.73 ms | 1.48 MB | 1.63 MB |
| Weekly schedule, 12 weeks | 0.0253 ms | 0.0269 ms | 0.0878 MB | 0.0899 MB |

The 800-event nested case is about 16.9 times faster with 33.6 times less
allocation in this run. Scaling from 100 to 800 is consistent with removing
per-ancestor merges; the final union still requires sorting. Stricter validation
has a measurable cost: constructors took about 50% longer (roughly 0.10 ms per
1,000), flat Groups about 9%, and daily recurrence about 16%. The small ICS and
schedule differences do not establish a meaningful speed change by themselves.
The correctness checks are retained despite their overhead. These are local
measurements, not production latency guarantees or timing assertions in tests.

For reproduction, use `mix run bench/hardening.exs` in each isolated revision
with this same fixture and dependencies. The complete mixed-workload benchmark
report was not regenerated; the new fixture specifically measures changed paths.

## Remaining verification limits and governance

The full quality gate ran on 1.18; the other two runtime pairs received source
compile/tests and package/notebook matrices, not independent full static-analysis
gates. Hosted GitHub CI, release automation, registry publication, installation
of a newly published package version, optional timezone HTTP updates, live
provider integrations, consumer transactions/crash recovery and production load
were not exercised. No claim of exhaustive protocol support, malformed-input
safety, optimal performance, or a bug-free library follows from these results.

No remote branch, tag, visibility, workflow, action pin, release configuration,
dependency constraint, lockfile or generated changelog was changed. No push,
publication, release or remote workflow was triggered. Network activity was
limited to reading documentation and retrieving/auditing dependencies. Existing
source behavior outside the evidenced fixes was retained. The working tree was
clean before the audit; all source changes in these commits belong to this work.

Normative contracts remain in SP.00/SP.02/SP.03/SP.05/SP.06/SP.07. This report
records evidence and decisions; it does not add future product requirements.
