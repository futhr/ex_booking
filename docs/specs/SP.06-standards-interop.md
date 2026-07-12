---
ex_booking:
  id: "SP.06"
  title: "Standards Interop Helpers"
  domain: booking
  status: normative
  priority: medium
  created: "2026-07-08"
  updated: "2026-07-11"
  tags: ["rrule", "ics", "jscalendar", "interop"]
  depends_on: ["R.02", "SP.01", "SP.03"]
---

# SP.06 — Standards Interop Helpers

This spec describes the three standards helper modules in `lib/ex_booking/`.
They are pure normalizers over caller-supplied data. They do not fetch calendars,
decode JSON, sync providers, write files, or execute network calls.

## `ExBooking.RRule`

File: `lib/ex_booking/rrule.ex`.

`ExBooking.RRule` expands a conservative RFC 5545 RRULE subset into UTC
`ExBooking.Interval` values over a caller-supplied horizon.

Supported rule parts:

- `FREQ=DAILY`
- `FREQ=WEEKLY`
- `INTERVAL`
- `COUNT`
- UTC `UNTIL`
- weekly `BYDAY`

Caller inputs:

- RRULE string or `%ExBooking.RRule{}`;
- `dtstart :: DateTime.t()`;
- `duration_min :: pos_integer()`;
- `from`/`until` horizon.

String rules and caller-constructed `%ExBooking.RRule{}` values pass through the
same validation. `interval` and `count` are positive integers, `until` is `nil`
or a `DateTime`, and weekly `byday` is `nil` or a non-empty list containing only
ISO weekdays `1..7`. Daily rules do not accept `byday`. Invalid hand-built rules
return a tagged error before a recurrence stream is created, so a zero interval
can never create a non-advancing stream.

Calendar frequencies preserve the `dtstart` wall-clock time in its IANA zone:

```text
next local date = Date.add(DateTime.to_date(dtstart), calendar offset)
DateTime.new(next local date, DateTime.to_time(dtstart), dtstart.time_zone)
  {:ok, dt}              -> dt
  {:ambiguous, first, _} -> first
  {:gap, _, after}       -> after
```

Every occurrence is shifted to UTC before interval construction. Output is
sorted by `start_at` and clipped to an increasing UTC-comparable horizon.
Unsupported parts fail as `{:unsupported, :rrule, part}` rather than being
ignored.

Full RFC 5545 recurrence semantics (`RDATE`, `EXDATE`, `BYSETPOS`, `WKST`,
`VTIMEZONE`, local recurrence sets) are adapter-layer concerns unless a future
repo task explicitly expands this module.

## `ExBooking.ICalendar`

File: `lib/ex_booking/icalendar.ex`.

`ExBooking.ICalendar.free_busy/1` scans unfolded iCalendar text for `FREEBUSY`
properties and normalizes periods into busy intervals.

Supported period forms:

- `start/end`
- `start/duration`

Constraints:

- date-times must be UTC in `YYYYMMDDTHHMMSSZ` form;
- positive durations follow RFC 5545 ordering: `PnW`, `PnD`, or a date/time
  form whose time components are `nH[nM[nS]]`, `nM[nS]`, or `nS`; weeks may
  not be mixed with days/time, seconds may not skip minutes after hours, and a
  trailing `T`, component mixtures, and zero total durations are rejected;
- comma-separated values are accepted;
- an absent `FBTYPE` means `BUSY`;
- `FBTYPE=FREE` contributes no busy interval;
- `BUSY`, `BUSY-UNAVAILABLE`, and `BUSY-TENTATIVE` contribute busy intervals;
- unrecognized `FBTYPE` tokens are treated as busy as the kernel's conservative
  normalization rule;
- other property parameters are accepted and ignored;
- malformed properties without the required `:` value separator fail as
  `{:invalid, :freebusy, :property}`;
- malformed periods fail explicitly.

Property and parameter names and registered token values are matched
case-insensitively. Period syntax is validated even for `FBTYPE=FREE`, then the
free periods are discarded. The helper returns merged, sorted `Interval` values
with `kind: :busy`.

## `ExBooking.JSCalendar`

File: `lib/ex_booking/jscalendar.ex`.

`ExBooking.JSCalendar.busy_intervals/1` accepts already decoded RFC 8984-style
JSCalendar maps. It maps `Event` and `Group` objects into UTC busy intervals.

Supported event fields:

- `@type: "Event"`
- `start`
- `timeZone`
- optional `duration`
- optional `status`
- optional `freeBusyStatus`

Behavior:

- `freeBusyStatus: "free"` is ignored;
- `status: "cancelled"` is ignored;
- `Group.entries` is an RFC-style JSON array represented as an Elixir list;
- local date-times accept an optional fractional second with up to six digits;
- duration seconds accept an optional fraction with up to six digits, retaining
  microsecond precision;
- floating events and recurrence rules are rejected;
- output intervals are merged, sorted, and `kind: :busy`.

An id-keyed object map is not a standard `Group.entries` representation and is
rejected as `{:invalid, :jscalendar, :entries}`. Fractional precision beyond the
kernel's microsecond `DateTime` precision is rejected rather than truncated.
Fractions must be non-zero and omit trailing zeros, and duration components must
follow the RFC grammar. Ambiguous and nonexistent local times both use the UTC
offset from before the timezone discontinuity, as required by JSCalendar; this
is deliberately different from availability-window gap snapping.

JSON decoding, complete JSCalendar recurrence support, provider-specific shapes,
and calendar transport belong in consumer/adaptor repositories.

## Sources

- R.02 (standards and ecosystem research).
- [RFC 5545 §3.2.9, Free/Busy Time Type](https://datatracker.ietf.org/doc/html/rfc5545#section-3.2.9).
- [RFC 5545 §3.8.2.6, Free/Busy Time](https://datatracker.ietf.org/doc/html/rfc5545#section-3.8.2.6).
- [RFC 8984 §1.4.2, Duration](https://www.rfc-editor.org/rfc/rfc8984.html#section-1.4.2).
- [RFC 8984 §1.4.5, LocalDateTime](https://www.rfc-editor.org/rfc/rfc8984.html#section-1.4.5).
