---
ex_booking:
  id: "SP.09"
  title: "Bounded civil-time occurrences"
  domain: booking
  status: normative
  priority: high
  created: "2026-10-15"
  updated: "2026-10-15"
  tags: [calendar, timezone, bounded-query]
  depends_on: ["SP.01", "SP.02", "SP.07", "SP.08"]
---

# SP.09 — Bounded civil-time occurrences

Version: 0.2.0. This is an additive pure calculation contract. The task list
records implementation and executed acceptance separately.

## Scope and distinction from recurrence

Enumerate a supplied weekday/time pattern over an explicit finite local-date
span, then filter its original UTC instants through a half-open query window.
This supports bounded calendar searches without replaying an ancient recurrence
prefix or inventing a replacement DTSTART. The operation supplies neither
duration, booking availability, scheduling, persistence nor execution authority.

[SP.08](SP.08-occurrence-enumeration.md) remains the original RRULE API: ordinals
count valid occurrences since its actual DTSTART, gaps do not consume COUNT and
efficient seek is not guaranteed. Civil queries have no DTSTART, COUNT, RRULE,
global ordinal or cursor. Their points must not be presented as SP.08 occurrence
ordinals. Availability-window gap snapping remains separately owned by SP.03.

## Public input and output

**CIV-01 — Closed finite query.** The facade is
`ExBooking.civil_occurrences(time, first_date, opts)` and delegates to
`ExBooking.CivilRecurrence.occurrences/3`. Identical validated input and database
contents produce identical values. `time` is an exact native ISO Time with whole
seconds and precision `{0, 0}`. `first_date` is an exact native ISO Date in years
0000–9999. Extra native fields and invalid calendar/time/date fields refuse.

`opts` is a proper keyword list with every following key exactly once. There
are no defaults; unknown, duplicate or missing keys refuse before callbacks.

| Key | Required value |
| --- | --- |
| days | Integer 1–366. Enumerate dates first_date through first_date + days - 1, inclusive; the complete span must stay within years 0000–9999. |
| weekdays | Nonempty ascending unique list of ISO weekdays 1–7, bounded to seven entries before traversal. |
| from, until | Exact structurally valid ISO DateTimes, years 0000–9999, valid UTF-8 time_zone (1–256 bytes) and zone_abbr (0–256 bytes), each offset component within ±93599 seconds and their total within [-89999, 93599] seconds. Normalize using the explicit UTC-only database; require from < until. Fractional instants preserve their native microsecond value/precision. |
| time_zone | Nonempty valid UTF-8 name, 1–256 bytes. |
| time_zone_database | Explicit Calendar.TimeZoneDatabase module or fully valid immutable SP.08 TimeZoneProvider. No ambient selection or text-to-module conversion. |
| gap_policy | Exactly skip or reject. |
| fold_policy | Exactly first, second, both or reject. Second selects the second instant of a fold; a unique label still produces its unique instant. |

The native result is `{:ok, [ExBooking.CivilOccurrence.t()]}`. Each value has
exactly `nominal` (the original ISO NaiveDateTime), `starts_at` (the original
UTC DateTime) and `resolution` (`:unique`, `:first_fold`, `:second_fold` or
`{:fold, index}` for index 3–732). The index is the position within this one
local label, never an ordinal counted from DTSTART. It
contains no query-relative or global ordinal, identifier, grant or callback.
These are native values, not a serialized format. The value is documented in
[SP.01](SP.01-data-model.md) and the facade in [SP.02](SP.02-public-api.md).

## Resolution, filtering and ordering

**CIV-02 — Local-date policy.** Check all input before invoking timezone
callbacks. Visit the at most 366 dates in increasing civil-date order. Skip
unselected weekdays without a timezone callback. Construct the exact whole-second
nominal label from each selected date/time and resolve through the supplied
database/provider. A gap is skipped or returns the fixed gap error, according
to gap_policy. A fold returns every strictly UTC-ordered original instant; apply
fold_policy to that complete set. First and second select positions 1 and 2;
both retains the complete set, including additional folds. Reject returns the fixed ambiguity error.
Never snap a nonexistent label forward or silently choose a different fold.

Validate every returned resolution, including every fold alternative before
selection: exact native ISO shape, matching nominal and zone, valid UTF-8
metadata with the same byte bounds and this civil profile's offset bounds. A fold must be strictly increasing in UTC. Round-trip
each resolved instant through the same supplied database/provider; the instant,
nominal label, zone and precision must agree. Malformed or refused results become
the fixed timezone-result error, without retaining callback payloads.
For an immutable provider this operation invokes its declared resolve/localize
callbacks and independently validates them under the civil profile. SP.08
TimeZoneProvider.from_naive/3 and shift_zone/3 keep their existing ±86400-second
helper contract; civil results are not passed through that narrower helper. Callback
implementation exceptions propagate as programming errors, as in SP.08.

**CIV-03 — Original points and horizon.** Apply the selected gap/fold policy
before the UTC filter. In particular, first-fold policy does not select the
second fold merely because the first lies before from. Gap/fold rejection
applies to every selected label in the local span, including labels outside the
UTC window. Normalize retained instants to Etc/UTC without clipping or changing
their nominal labels, then include exactly `from <= starts_at < until`.
Conversion outside supported UTC years refuses rather than clamping a point.

Return all retained points in strictly increasing UTC order, irrespective of
local-date order. Duplicate UTC results refuse as inconsistent timezone output;
do not coalesce them. At most 732 points can be returned. The result is complete
for the selected finite local span only: an empty list means no matching point
there, not exhaustion of all later dates. There is no partial result on failure.

**CIV-04 — Work and retry.** The finite span and localization ceiling are the
complete work budget. There are at most 366 local resolutions and 732 round-trip
localizations across the entire query. Before localizing any alternative of a
new label, require its complete candidate count to fit the remaining budget;
otherwise return `{:error, {:limit, :civil_occurrences, :work}}`. Gaps consume
zero localizations. Policy and UTC filtering do not refund work. Classical
unique/twofold providers always fit this ceiling for all 366 dates. No hidden
prefix traversal, cursor validation, network lookup, wall-clock observation or
random operation occurs. The supplied callback's own implementation/runtime is
consumer-owned; this operation does not promise a wall-time deadline for it.

Repeat the same query for a logical retry. A caller extending the local-date
span owns the complete immutable query/database basis and any global ordering,
deduplication, durable identity and downstream authorization. Do not start a new
RRULE to manufacture an ordinal from that extension. No library state exists
to cancel, restart, migrate, transfer or restore, and a timezone basis label
would not authenticate the supplied contents. No unused basis option is accepted.

## Error vocabulary and compatibility

**CIV-05.** Caller validation returns `{:error, {:invalid, :civil_occurrences,
field}}`, where field is one of `:options`, `:time`, `:first_date`, `:days`,
`:weekdays`, `:from`, `:until`, `:horizon`, `:time_zone`,
`:time_zone_database`, `:gap_policy`, `:fold_policy`, `:time_zone_result` or
`:coordinate_range`. Gap/fold rejection returns respectively
`{:error, {:gap, :civil_occurrences}}` or
`{:error, {:ambiguous, :civil_occurrences}}`. Exceeding the localization budget
returns `{:error, {:limit, :civil_occurrences, :work}}`. Errors embed no supplied values,
provider context or callback reason. Invalid caller-native fields refuse before
date arithmetic. Existing RRule/occurrence, availability, interval, timezone
helper and option defaults/errors are unchanged. No dependency is introduced.

## Optional complete civil resolution

**CIV-06.** An immutable TimeZoneProvider module may additionally implement
`resolve_civil(nominal, zone_name, context)`. It accepts the same explicit inputs
as resolve/3 and returns its existing unique/twofold/gap/refusal shapes or
`{:ambiguous, candidates}`, where candidates is a proper list of 2–732 native
local DateTimes. The list retains every alternative, strictly ordered by UTC;
empty/singleton/improper/oversized lists refuse. Positions 1/2 retain the old
first_fold/second_fold tags; later positions use `{:fold, index}`. A callback
must not silently discard intermediate candidates to fit a twofold interface.

Only SP.09 uses this optional callback, preferring it when exported. Its refusal,
malformed result or implementation fault must never fall back to resolve/3.
If absent, call the original resolve/3 once; that legacy callback still accepts
only its original result shapes. Calendar.TimeZoneDatabase modules retain their
existing one/twofold interface. The provider value, required resolve/localize
callbacks and constructor validity are unchanged. SP.08 original occurrences and
TimeZoneProvider.from_naive/3 still call only resolve/3; shift_zone/3 still calls
localize/3 with its original offset profile. This additive civil callback cannot
widen the legacy interfaces through incidental module capability.

Every alternative round-trips before policy and UTC filtering, including one
that policy will discard. A complete candidate list exceeding the remaining
732-localization budget refuses before any of that label's localizations; no
partial output or truncated candidate set is returned. A caller owns splitting
an intentionally larger finite query, immutable inputs, result ordering and
identity. Single-label queries can represent every supported candidate without
replaying an ancient recurrence prefix.

## Independent acceptance

| Case | Requirements and observation / falsifier |
| --- | --- |
| CIV-T1 | 01–04: Literal UTC dates, exact weekday masks, both UTC boundaries, fractional query endpoints and the final supported date produce exact original points; a point clipped to from or an extra weekday fails. |
| CIV-T2 | 02–03: Independently stated Stockholm and New York spring gaps and autumn folds cover every policy; first outside/second inside never substitutes under first policy; rejection applies before UTC filtering. |
| CIV-T3 | 01/05: Unknown/duplicate/missing options, improper/oversized lists, booleans, invalid/native-extra date/time/datetime fields, precision, overflowed spans, bad modules/providers and malformed horizons refuse before any counting callback. |
| CIV-T4 | 02/04/05: Instrumented immutable providers establish the finite callback bound and independent concurrent contexts. Refused/malformed/reversed-fold/mismatching round-trip/duplicate-UTC output yields fixed errors without private payloads; implementation faults propagate. |
| CIV-T5 | 01–04: Bounded StreamData UTC patterns agree with an independent day/weekday oracle. Partition/union queries agree after sorting where their explicit policies succeed. Retry is identical and unrelated ambient timezone settings have no effect. |
| CIV-T7 | 02–06: Independent threefold and maximum 732-candidate providers exercise every policy and stable local fold positions; invalid discarded alternatives still refuse. Exact 732 total localizations succeeds, the next complete label refuses before localization, and 733 candidates refuse. Optional callback faults/refusals never fall back; legacy helpers/occurrences never invoke it. The actual archive/no-start consumer exercises a threefold query. |
| CIV-T6 | 01–05: Public facade/domain doctests and actual extracted archive consumer execute the new API with no application start. Existing SP.08 COUNT/ordinal/second-fold DTSTART and availability gap tests retain their original behavior. |

These are software obligations, not proof of a consumer's clock, durable
scheduler, installed timezone authenticity or physical effect. Record executed
commands and actual scope in the task list before claiming acceptance.

## Sources and offset profile

The selected total-offset range is the recommended UT-offset range in
[RFC 9636 section 3.2](https://www.rfc-editor.org/rfc/rfc9636.html#section-3.2).
This operation does not parse TZif or claim complete timezone-data conformance.
Explicit wider civil-profile validation preserves interoperability with retained
TZif data without widening SP.08 helper or original-occurrence behavior.
