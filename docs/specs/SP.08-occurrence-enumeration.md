---
ex_booking:
  id: "SP.08"
  title: "Original Occurrence Enumeration"
  domain: booking
  status: normative
  priority: high
  created: "2026-10-13"
  updated: "2026-10-13"
  tags: ["rrule", "occurrences", "pagination", "bounds"]
  depends_on: ["SP.01", "SP.02", "SP.06", "SP.07"]
---

# SP.08 — Original Occurrence Enumeration

This is an additive pure recurrence contract. It returns original calendar
occurrences for calendar previews, reminders, reporting and other consumers.
It owns no execution, persistence, reservation, clock trust or application
identity. Implementation progress belongs in the task list.

The existing duration-bearing `expand_rrule/4` and `RRule.expand/5` still return
clipped intervals. Availability windows still snap DST gaps forward. This API
returns neither intervals nor jobs and does not change either existing policy.

## Inputs and public API

**OCC-01.** The public facade and owning domain operation are:

```elixir
ExBooking.occurrences(rule, dtstart, opts)
ExBooking.RRule.occurrences(rule, dtstart, opts)
# => {:ok, %ExBooking.OccurrencePage{}} | {:error, reason}
```

`rule` is a supported RRULE string (at most 4096 bytes) or validated
`%ExBooking.RRule{}`. Reuse SP.06 parsing/validation: DAILY/WEEKLY, positive
INTERVAL, optional positive COUNT or UTC UNTIL (mutually exclusive), weekly
BYDAY in ISO weekdays and Monday week anchoring. Unknown parts reject. No
new dependency, provider fetch or broader RFC recurrence grammar is introduced.
Native BYDAY lists are bounded to seven entries before normalization.

`dtstart` is a structurally valid ISO-calendar DateTime in years 0000–9999.
Its nominal local fields and supplied UTC offset must correspond to the
explicit time-zone database. An ambiguous DTSTART may designate either actual
fold instant; preserve that supplied instant. A nonexistent or mismatched
DTSTART rejects. Subsequent ambiguous occurrences always use the first instant.
Existing APIs retain their custom-calendar and datetime contracts.
Offset components and their sum must each lie within ±86400 seconds.

| Option | Required / default | Contract |
| --- | --- | --- |
| `:from`, `:until` | Required together | Structurally valid ISO DateTimes; normalize to UTC; increasing half-open query horizon |
| `:time_zone_database` | Required | Explicit Calendar.TimeZoneDatabase module or validated TimeZoneProvider value; no application-environment selection |
| `:time_zone_basis` | Required | Nonempty valid UTF-8 binary, at most 256 bytes; caller's identifier for the exact installed database data |
| `:limit` | Default 128 | Integer 1–1024; maximum occurrences returned per page |
| `:work_limit` | Default 4096 | Integer 1–100000; maximum candidate positions resolved in this call, including prefix/cursor validation |
| `:cursor` | Default nil | The exact native OccurrenceCursor returned for this query, or nil for its first page |

Unknown/duplicate option keys, malformed containers, forged temporal fields,
out-of-range bounds and invalid native structs reject before recurrence traversal.
No `:now`, duration, consumer identity or booking resource is required.
The basis identifier attributes caller-selected data; it is not authentication
of the database contents. The consumer must hold that data immutable while
using a cursor. The library performs no I/O to verify or acquire it.

## Values and ordering

**OCC-02.** Values are native immutable structs, not a wire format:

| Struct | Fields |
| --- | --- |
| Occurrence | `nominal`: original local NaiveDateTime; `starts_at`: original UTC DateTime; `ordinal`: positive index among valid occurrences since DTSTART; `resolution`: `:unique`, `:first_fold` or `:second_fold` |
| OccurrencePage | `occurrences`: ordered list; `next_cursor`: OccurrenceCursor or nil |
| OccurrenceCursor | `basis`: complete normalized query basis; `next_offset_days`: next calendar candidate offset from DTSTART; `emitted_count`: valid occurrences before that candidate |

The basis contains normalized rule, validated DTSTART, UTC from/until, database
module/provider (including its exact context) and time-zone basis identifier. Limit/work_limit may change between pages;
semantic query fields may not. The cursor is neither a signed token nor proof
that a consumer processed previous results.

Returned starts are never clipped or shifted to the query start. Filtering is
`from <= starts_at < until`. Ordinals and nominal/UTC instants are independent
of horizon and page size. Dates skipped for gaps consume no ordinal or COUNT.
Valid occurrences before the horizon consume COUNT and ordinals. UTC UNTIL is
inclusive for the recurrence; query until is exclusive. Results increase by UTC
instant; inconsistent non-increasing database resolution rejects rather than
silently reordering a cursor stream.

## Deterministic enumeration and continuation

**OCC-03.** Daily offsets are `n * INTERVAL`. Weekly without BYDAY uses
`n * 7 * INTERVAL`. Weekly BYDAY enumerates sorted distinct weekdays in active
Monday-anchored weeks, discarding starts before DTSTART. Duplicate BYDAY input
is normalized consistently with the validated recurrence. A mismatching DTSTART
weekday does not add an extra BYDAY occurrence.

For each candidate local date, combine its date with DTSTART's wall time.
Resolve with the supplied database: unique uses that instant; ambiguity uses
the first; gap skips. Preserve DTSTART itself when its candidate offset is zero,
including a supplied second-fold instant. Compare UTC after resolution, apply
global COUNT/UNTIL, then horizon filtering. Preserve microsecond precision.
Bound dates before Date arithmetic; overflow cannot raise or wrap.

Traversal ends after the final local query date (resolved using the explicit
database), recurrence COUNT/UNTIL, or the representable calendar end. The final
local date is included in candidate inspection; exact UTC filtering determines
whether its instant is before query until. No sparse recurrence can walk
indefinitely looking beyond the horizon.
Both interval expansion and occurrence enumeration share the same normalized
candidate-position rules; their duration/filtering and explicit-database seams
remain separately owned.

**OCC-04.** A full page returns the next candidate position when exhaustion
has not yet been established. Therefore a final empty continuation page with
nil cursor is permitted. A cursor never requires speculative resolution of an
extra candidate merely to prove whether a full page is last.

Every cursor is shape/basis checked and its candidate position and emitted
prefix count are verified against the recurrence. The initial implementation
may replay the prefix from DTSTART under the same work bound. An independently
proved arithmetic seek is also permitted; it must count gaps and COUNT exactly.
An incorrect count or noncandidate position rejects. A coherent alternative
checkpoint is indistinguishable from an originally returned one in this pure
API: verification establishes recurrence position, not issuance or consumer
processing history. The consumer owns progression and must retain its original
cursor when completeness matters.
No mutable iterator/process/global cache is used.

**OCC-05.** Each visited candidate consumes one work unit before resolution,
including gaps, pre-horizon positions and cursor verification. No wall-time
deadline, inferred elapsed time or arbitrary function-call count substitutes
for this deterministic budget. Reaching the work bound before a page or
exhaustion is established returns a work-limit error, without a partial page
or advanceable cursor. A caller may explicitly retry with a larger supported
budget; the library never increases it silently.

Long historical queries can therefore fail predictably rather than scan without
bound. Limits affect success/cardinality per page, never the identity of any
returned occurrence. This is bounded computation, not an efficient-seek guarantee.

## Errors, purity and compatibility

**OCC-06.** Existing RRULE parse/validation errors remain unchanged.
The new API additionally returns:

```text
{:invalid, :occurrences, :options | :arguments | :rule_size |
  :time_zone_database | :time_zone_basis | :limit | :work_limit |
  :cursor | :dtstart | :time_zone_order}
{:stale, :occurrences, :cursor_basis}
{:limit, :occurrences, :work}
```

These are reasons inside `{:error, reason}`. Malformed caller data returns
errors without raising. Database callbacks must satisfy Calendar's contract;
a callback implementation fault is a programming error, not a missing occurrence.
No error embeds credentials or unrelated consumer data.

Identical validated inputs and the same database contents produce identical
ordered values. Logical retries recompute the same page; callers own cursor
custody, processed-result deduplication, durable identity and any later effect.
Changes to time-zone data require a new basis and query; old cursors reject.
There is no durable state to migrate, cancel, restore or fence in this library.
Existing expand/availability outputs, defaults and errors remain unchanged.

## Acceptance

| Case | Requirements | Independent expectation / falsifier |
| --- | --- | --- |
| OCC-T1 | 01–03 | A 06:00 occurrence queried from 06:05 is absent, never rewritten to 06:05; query from 05:55 returns original 06:00 |
| OCC-T2 | 02–04 | Whole result equals concatenated bounded pages at different limits; nominal/UTC/ordinal are stable across overlapping horizons |
| OCC-T3 | 01–03 | Independent Stockholm/New York gap/fold vectors: gaps do not consume COUNT, future folds choose first once, supplied second-fold DTSTART is retained |
| OCC-T4 | 01–03 | DAILY/WEEKLY/INTERVAL/BYDAY, Monday anchors, COUNT before filtering and inclusive UNTIL/exclusive horizon agree with an independent calendar-day oracle |
| OCC-T5 | 01, 04, 06 | Reject duplicate/unknown options, forged dates/rules, mismatched basis, tampered cursor and missing database; no raising or partial success |
| OCC-T6 | 03–05 | Empty/sparse/ancient horizons and gap-heavy cursor replay exhaust a small budget deterministically; exact boundary succeeds; no work beyond the finite horizon |
| OCC-T7 | 02–06 | Fractional seconds, year bounds, empty final continuation and retries preserve deterministic ordering and exact values |
| OCC-T8 | 01, 06 | Existing RRULE/availability corpus is unchanged; independent archive consumer enumerates reminders and calendar previews without application/process/I/O additions |

Examples become runnable doctests once implemented. Properties must be
non-vacuous, using an independently enumerated calendar-day reference rather
than the production candidate generator. SP.07 owns full quality/archive checks.
No package, application or physical-device behavior is inferred from prose.

## Sources

SP.06 owns the existing narrow recurrence grammar and gap policy.
[RFC 5545 §3.3.10](https://www.rfc-editor.org/rfc/rfc5545.html#section-3.3.10)
defines recurrence COUNT and exclusion of nonexistent local times. Pagination,
work budgets and the native cursor are package-defined additions, not an RFC
interchange format or a complete recurrence-set implementation.

## Explicit immutable timezone providers

**OCC-07.** `ExBooking.TimeZoneProvider.new(module, context)` accepts an existing
loaded module implementing `resolve/3` and `localize/3`, plus an explicit opaque
binary context of 0–1048576 bytes. It returns a TimeZoneProvider with exactly
module/context fields or `{:error, :invalid_time_zone_provider}`. No binary is
converted into a module atom. Consumer code implements this public behaviour:

- `resolve(nominal, zone_name, context)` returns `{:ok, local_datetime}`,
  `{:ambiguous, first_local_datetime, second_local_datetime}`, `:gap`, or
  `{:error, reason}`. Successful datetimes preserve the exact nominal fields/
  precision and zone name. Fold candidates increase strictly by UTC instant.
- `localize(datetime, zone_name, context)` returns `{:ok, local_datetime}` or
  `{:error, reason}`; success preserves the exact UTC instant/precision and has
  the requested zone name.

Returned datetimes must satisfy OCC-01's ISO/year/offset bounds. Invalid return
shapes, changed wall/instant coordinates, reversed/duplicate folds or malformed
values return `{:error, :invalid_time_zone_result}` through the public provider
helpers. Callback refusal payloads normalize to `{:error, :time_zone_provider_refused}`
in both public helpers, without copying foreign values or context.
Callback exceptions remain implementation faults, as for Calendar's
module interface; no fault becomes a missing occurrence. Providers are trusted
installed pure code, not executable profile input. They must not read clocks,
application environment or mutable registries, fetch data or perform I/O.
Context is explicit immutable data, retained in the native cursor basis; it is
not a credential store or a portable token. The caller owns its custody.

`TimeZoneProvider.valid?/1` rechecks the complete native struct and module seams.
`TimeZoneProvider.from_naive/3` and `shift_zone/3` take the same arguments as the
corresponding DateTime operations, with the explicit module/provider as their
last argument. They also retain ordinary Calendar database module behavior.
The provider gap result is `:gap`; occurrence enumeration skips it. No gap
boundary or availability snapping is inferred from this recurrence-only seam.

SP.08 accepts that provider as :time_zone_database. Its full module/context is
bound alongside the caller's time_zone_basis. A changed context invalidates old
cursors even if the basis string is accidentally reused. Existing module input,
DTSTART fold selection, recurrence policies, limits and all availability/interval
APIs stay unchanged. This addition supplies no default timezone implementation,
TZif parser, global zone registry or application identity.

OCC-T9 exercises two independent provider contexts in one process, immutable
cursor binding, malformed/oversize/native provider refusal, invalid output and
fold ordering. Explicit providers for Stockholm/New York agree with the existing
module-based DST corpus and independent UTC expectations, including second-fold
DTSTART, skipped gaps, COUNT and changing page limits. Archive consumers exercise
this public seam without application configuration or shared mutable state.

SP.09 additionally owns an optional resolve_civil/3 callback for complete bounded
civil ambiguities. SP.08 and the public from_naive/3 helper never select that
callback; their resolve/3 return shapes, work accounting and original ordinals
remain unchanged.
