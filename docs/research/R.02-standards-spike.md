---
ex_booking:
  id: "R.02"
  title: "Standards Interop Spike"
  domain: booking
  status: accepted
  priority: medium
  created: "2026-07-08"
  updated: "2026-07-08"
  tags: ["rrule", "ics", "jscalendar", "standards"]
  depends_on: ["R.01", "SP.07"]
---

# R.02 — Standards Interop Spike

## Question

How far should the kernel go on RRULE, ICS free/busy, and JSCalendar interop
without violating the dependency and purity constraints?

## Sources

- RFC 5545 — iCalendar: https://www.rfc-editor.org/info/rfc5545/
- RFC 7953 — Calendar Availability: https://www.rfc-editor.org/info/rfc7953/
- RFC 8984 — JSCalendar: https://www.rfc-editor.org/info/rfc8984/
- Hex `ical`: https://hex.pm/packages/ical
- Hex `rrule`: https://hex.pm/packages/rrule
- Hex `ex_tempo`: https://hex.pm/packages/ex_tempo

## Findings

`ical` is the best fit for full iCalendar read/write when this library is ready
to accept a dependency: it targets RFC 5545 and exposes recurrence parsing.
`rrule` is focused on recurrence expansion and wraps `rust-rrule`, which adds a
Rust/NIF operational concern. `ex_tempo` has broader RFC 5545 and RSCALE
ambition, but is too broad for the current tiny runtime surface.

RFC 5545 recurrence is large: complete support means BYSETPOS, BYMONTH,
BYMONTHDAY, ordinal BYDAY, WKST, RDATE, EXDATE, VTIMEZONE, and local wall-time
recurrence semantics. Implementing all of that in-house would become a calendar
engine, not a booking kernel.

## Decision

Keep runtime dependencies unchanged. Implement only small, explicit,
dependency-free adapters:

- RRULE subset expansion for `FREQ=DAILY` and `FREQ=WEEKLY`, with `INTERVAL`,
  `COUNT`, `UNTIL`, and weekly `BYDAY`.
- ICS `VFREEBUSY` `FREEBUSY` period normalization into `Interval` lists.
- JSCalendar decoded-map normalization for event busy intervals.

Unsupported RRULE and calendar fields must fail explicitly instead of being
ignored. Full RFC 5545/JSCalendar fidelity remains a future optional adapter
layer.
