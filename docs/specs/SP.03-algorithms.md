---
ex_booking:
  id: "SP.03"
  title: "Algorithms"
  domain: booking
  status: normative
  priority: critical
  created: "2026-07-08"
  updated: "2026-07-08"
  tags: ["algorithms", "interval-algebra", "dst", "slotting", "conflict-detection"]
  depends_on: ["R.01", "SP.01"]
---

# SP.03 — Algorithms

## 1. Interval algebra (`ExBooking.Interval`)

The foundation. All intervals are half-open `[start_at, end_at)` UTC `DateTime`s.

| Operation | Contract |
|---|---|
| `overlaps?(a, b)` | `a.start_at < b.end_at and b.start_at < a.end_at`. Touching intervals do not overlap. |
| `contains?(outer, inner)` | `outer.start_at <= inner.start_at and inner.end_at <= outer.end_at` |
| `subtract(a, b)` | `a` minus `b`: `[]`, one, or two intervals. Preserves `a`'s `kind`/`meta`. |
| `subtract_all(as, bs)` | Fold `subtract` over normalized `bs`; result is sorted, non-overlapping. |
| `merge(intervals)` | Sort by start, coalesce overlapping *and touching* intervals. Result is the normal form: sorted, disjoint, non-adjacent. |
| `clip(a, bounds)` | Intersection of `a` with `bounds`, or `nil` when disjoint. |
| `inflate(a, before_min, after_min)` | Widen: start −`before_min`, end +`after_min`. Used for buffer application. |
| `duration_min(a)` | Whole minutes between endpoints. |

Laws (property-tested, SP.06):

- `overlaps?` is symmetric; an interval never overlaps its own complement pieces.
- `subtract(a, b)` pieces never overlap `b`, are contained in `a`, and are disjoint.
- `merge` is idempotent; total coverage is preserved when inputs don't overlap.
- `clip(a, bounds)` result is contained in both; `inflate` then `clip` by the same
  bounds never exceeds bounds.

## 2. Wall-time expansion and DST

`AvailabilityRule.windows` are wall time in the rule's timezone. Expansion of one
window on one date follows this exact procedure (`ExBooking.Schedule.expand/3`):

```text
resolve(date, time, tz) =
  case DateTime.new(date, time, tz) do
    {:ok, dt}              -> dt                # unambiguous
    {:ambiguous, first, _} -> first             # fall-back: FIRST occurrence
    {:gap, _before, after} -> after             # spring-forward: snap FORWARD
  end

expand_window(window, date, tz) =
  start = resolve(date, window.start_time, tz)
  end_date = if window.end_time <= window.start_time, do: date + 1 day, else: date
  end_  = resolve(end_date, window.end_time, tz)     # <= handles cross-midnight
  if start < end_, do: [Interval(start, end_)], else: []   # gap-snap can empty a window
```

Worked examples (dates verified against the 2026 IANA tz data; these are the
fixture cases in `test/support/dst_fixtures.ex`):

- `Europe/Stockholm`, 2026-03-29 (spring forward, 02:00→03:00): a window
  `02:30–04:00` resolves its start via the gap rule to `03:00` local — the
  expanded interval is `03:00–04:00` CEST. No phantom 02:xx slots may be emitted.
- `America/New_York`, 2026-11-01 (fall back, 02:00→01:00): a window starting
  `01:30` resolves to the **first** occurrence (01:30 EDT, the earlier UTC
  instant). After UTC normalization, any duplicate slots produced by the repeated
  wall hour are removed by `merge`/`uniq_by(start_at)` — a wall time never yields
  two offered slots.
- A window `22:00–02:00` on any date expands to `[22:00 that day, 02:00 next
  day)` in the rule timezone before UTC normalization.

These rules are fixed; consumers needing a different DST policy must pre-expand
windows themselves and pass blackouts/overrides instead.

## 3. Availability assembly pipeline (`ExBooking.Availability`)

Input: meeting type, resources, rules, `from`/`until`/`now`.

```text
1. expand    each rule's weekly windows over [from, until] in rule TZ (per §2)
2. override  replace expanded windows on dates present in rule.overrides
             (empty override windows remove the day)
3. blackout  subtract rule.blackouts
4. normalize to UTC intervals; merge to normal form            → offerable time
5. busy      per resource: merge resource.busy, inflate each busy interval by
             effective buffers (meeting_type.buffers || rule.buffers)
6. subtract  offerable − inflated busy                          → free time
7. slot      generate candidate slots on the slot grid (§4)
8. filter    drop slots per the policy definitions below
9. combine   per meeting_type.participants mode (§5)
10. sort     ascending start_at, tie-break by resource id       → slots
```

Policy definitions for step 8 (all comparisons on UTC instants unless stated):

- **Lead time** — drop a slot when
  `slot.start_at < DateTime.add(now, rule.lead_time_min, :minute)`.
- **Booking window** — when `rule.booking_window_days = n` (nil = unbounded),
  the last bookable *calendar date* is `today_in_rule_tz + n days`, where
  `today_in_rule_tz = DateTime.shift_zone!(now, rule.timezone) |> DateTime.to_date()`.
  Drop a slot when its start, shifted to the rule timezone, falls on a later date.
- **Daily cap** — when `rule.max_per_day = n` (nil = uncapped), count the
  resource's busy intervals with `kind == :busy` (holds do not count) whose
  start, shifted to the rule timezone, falls on the slot's rule-timezone date.
  Drop the slot when that count `>= n`.

Buffers inflate *busy* time, not slots: a buffer prevents a new booking from
starting too close to existing commitments but does not consume offerable time at
the edges of the working day.

## 4. Slot generation (`ExBooking.Slotting`)

The grid step is `slot_interval_min || duration_min` — **independent of
duration**. Within each free interval:

```text
candidates(free, duration, step) =
  starts = free.start_at, free.start_at + step, free.start_at + 2·step, …
  keep start while start + duration <= free.end_at
```

Grid anchoring defaults to the free interval's start (`align: :free_start`), not
to `:00` of the hour. Callers may pass `align: :clock` to anchor the grid to UTC
clock boundaries and skip the partial leading offset inside each free interval.
A 30-minute meeting on a 15-minute grid over a 09:00–10:00 free window yields
09:00, 09:15, 09:30. The same meeting over a 09:07–10:00 free window yields
09:07, 09:22 by default, or 09:15, 09:30 with `align: :clock`.

## 5. Participant modes

- `:one` — each resource yields slots independently; a slot is offered if *any*
  eligible resource is free (assignment picks the winner, SP.04).
- `:collective` — intersection: a slot is offered only where *all* listed
  resources are free (free-time intersection before slotting).
- `:pool` — capacity-aware: a slot is offered while the number of free resources
  ≥ `meeting_type.capacity_required`; resources with `capacity > 1` count
  remaining seats (capacity − overlapping bookings).

## 6. Conflict detection

A requested slot conflicts iff, for a required resource, the slot inflated by
effective buffers overlaps any busy interval:

```elixir
conflict? = Interval.overlaps?(Interval.inflate(slot, before, after), busy)
```

Note the asymmetry with §3.5: at assembly time buffers inflate busy; at validation
time inflating the slot is equivalent and cheaper (one inflation instead of many).
Both directions must agree — property-tested.

## 7. Complexity targets

With `n` busy intervals per resource, `w` expanded windows, `r` resources:
assembly is `O(r · (n log n + w log w))` (sort-merge based subtraction, no
quadratic scans). Slot emission is lazy-friendly (streams internally) but returns
lists at the API boundary for determinism.
