---
ex_booking:
  id: "SP.03"
  title: "Temporal Availability Algorithms"
  domain: booking
  status: normative
  priority: critical
  created: "2026-07-08"
  updated: "2026-07-08"
  tags: ["interval", "schedule", "availability", "slotting", "policy"]
  depends_on: ["SP.01"]
---

# SP.03 — Temporal Availability Algorithms

This spec maps to these files:

```text
lib/ex_booking/interval.ex
lib/ex_booking/schedule.ex
lib/ex_booking/slotting.ex
lib/ex_booking/availability.ex
lib/ex_booking/policy.ex
```

It does not describe assignment, lifecycle, standards interop, or external
calendar sync. Those live in `SP.04`, `SP.05`, `SP.06`, or consumer repositories.

## `ExBooking.Interval`

All intervals are half-open `[start_at, end_at)` `DateTime`s. Public operations:

| Function | Contract |
|---|---|
| `new/3`, `new!/3` | Build a valid interval where `end_at > start_at` |
| `overlaps?/2` | `a.start_at < b.end_at and b.start_at < a.end_at`; touching does not overlap |
| `contains?/2` | `outer.start_at <= inner.start_at and inner.end_at <= outer.end_at` |
| `subtract/2` | Return `a - b` as zero, one, or two intervals |
| `subtract_all/2` | Subtract normalized intervals from many intervals |
| `merge/1` | Sort and coalesce overlapping or touching intervals |
| `clip/2` | Return intersection or `nil` |
| `inflate/3` | Widen by minutes before and after |
| `duration_min/1` | Whole-minute duration |

`subtract/2` preserves the minuend's `kind` and `meta`. `merge/1` returns normal
form: sorted, disjoint, and non-adjacent.

## `ExBooking.Schedule`

`Schedule.expand/3` expands an `ExBooking.AvailabilityRule` over a UTC
`from`/`until` horizon. Weekly windows and overrides are wall time in
`rule.timezone`.

Wall-time resolution is fixed:

```text
DateTime.new(date, time, timezone)
  {:ok, dt}              -> dt
  {:ambiguous, first, _} -> first
  {:gap, _before, after} -> after
```

Cross-midnight windows use the next calendar day when `end_time <= start_time`.
Expanded output is clipped to the horizon and merged.

Overrides replace the regular windows for a date. An override with `windows: []`
removes the whole day. Blackouts are subtracted after expansion.

## `ExBooking.Slotting`

`Slotting.generate_slots/4` emits candidate slots inside one free interval.
`Slotting.generate_all/4` applies the same logic to many intervals.

The grid step is always caller-supplied by the meeting type pipeline:

```text
step = meeting_type.slot_interval_min || meeting_type.duration_min
```

The step is independent of meeting duration. A 30-minute booking on a 15-minute
grid over 09:00-10:00 yields starts at 09:00, 09:15, and 09:30.

Supported alignment:

- `align: :free_start` — default; grid starts at each free interval start.
- `align: :clock` — grid is anchored to UTC clock boundaries and skips any
  partial leading offset inside the free interval.

Output is sorted by `start_at` and de-duplicated by start time by callers that
merge resource results.

## `ExBooking.Policy`

`Policy.violations/4` returns all policy failures for a slot/resource/rule/now
combination.

Policy checks:

- **Lead time** — reject when `slot.start_at < now + lead_time_min`.
- **Booking window** — compare slot start date in the rule timezone with
  `now`'s rule-timezone date plus `booking_window_days`.
- **Daily cap** — count only resource busy intervals with `kind == :busy`; holds
  do not count toward the cap.

`Policy.notice_ok/3` is shared by cancellation and reschedule policy checks.
`nil` policy allows the action. `allowed: false` returns `{:error, :not_allowed}`.
Insufficient notice returns `{:error, :min_notice}`.

## `ExBooking.Availability`

`Availability.assemble/4` is the slot-search pipeline used by
`ExBooking.available_slots/4` and rejected-decision alternatives.

```text
resources + rules are paired positionally
  -> expand rule windows with Schedule.expand/3
  -> subtract buffer-inflated resource busy intervals
  -> generate slots with Slotting.generate_all/4
  -> filter Policy.violations/4
  -> combine by participant mode
  -> sort deterministically
```

Participant modes:

- `:one` — slots are offered when any resource is eligible.
- `:collective` — slots are offered only where all listed resources are free.
- `:pool` — slots are offered when available seats meet
  `meeting_type.capacity_required`; resource `capacity > 1` contributes remaining
  seats after overlapping busy intervals.

`Availability.validate/5` and `Availability.eligible/5` check a requested slot.
They return every failing reason rather than stopping at the first failure.
Conflict detection inflates the requested slot by effective buffers and checks
for overlap with resource busy intervals.

## Deterministic Ordering

The availability pipeline sorts slots ascending by `start_at`. Where resources
are later assigned, `SP.04` supplies the final resource-id tie-break. No function
reads the clock; every time-relative decision uses caller-supplied `now`.
