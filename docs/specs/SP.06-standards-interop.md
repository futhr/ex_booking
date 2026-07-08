---
ex_booking:
  id: "SP.06"
  title: "Standards Interop Helpers"
  domain: booking
  status: normative
  priority: medium
  created: "2026-07-08"
  updated: "2026-07-08"
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

Output is sorted by `start_at` and clipped to the horizon. Unsupported parts fail
as `{:unsupported, :rrule, part}` rather than being ignored.

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
- comma-separated values are accepted;
- parameters such as `FBTYPE` are accepted and ignored;
- malformed periods fail explicitly.

The helper returns merged, sorted `Interval` values with `kind: :busy`.

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
- `Group.entries` may be a list or id-keyed map;
- floating events and recurrence rules are rejected;
- output intervals are merged, sorted, and `kind: :busy`.

JSON decoding, complete JSCalendar recurrence support, provider-specific shapes,
and calendar transport belong in consumer/adaptor repositories.
