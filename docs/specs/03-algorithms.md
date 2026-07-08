# Spec 03 — Algorithms

**Status:** normative

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

Laws (property-tested, Spec 06):

- `overlaps?` is symmetric; an interval never overlaps its own complement pieces.
- `subtract(a, b)` pieces never overlap `b`, are contained in `a`, and are disjoint.
- `merge` is idempotent; total coverage is preserved when inputs don't overlap.
- `clip(a, bounds)` result is contained in both; `inflate` then `clip` by the same
  bounds never exceeds bounds.

## 2. Wall-time expansion and DST

`AvailabilityRule.windows` are wall time in the rule's timezone. Expansion to a
concrete date uses `DateTime.new/4` with the `tz` database:

- **Unambiguous** wall time → that instant.
- **Ambiguous** (fall-back; two instants exist) → **first occurrence** (earlier UTC).
- **Gap** (spring-forward; instant doesn't exist) → **snap forward** to the first
  valid instant after the gap.

A window whose `end_time <= start_time` crosses midnight and expands into the next
calendar day. Duplicate wall-time slots produced on fall-back days are deduplicated
after UTC normalization. These rules mirror behavior validated in production
schedulers and are fixed — consumers needing different DST policy must pre-expand
windows themselves.

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
8. filter    drop slots starting before now + lead_time_min;
             drop slots outside booking_window_days (evaluated in rule TZ);
             drop slots on days where the resource's existing bookings
             (busy with kind != :hold counts) >= max_per_day
9. combine   per meeting_type.participants mode (§5)
10. sort     ascending start_at, tie-break by resource id       → slots
```

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

Grid anchoring is to the free interval's start (not to :00 of the hour); an
optional `:align` opt may later anchor to clock boundaries (roadmap). A
30-minute meeting on a 15-minute grid over a 09:00–10:00 free window yields
09:00, 09:15, 09:30.

## 5. Participant modes

- `:one` — each resource yields slots independently; a slot is offered if *any*
  eligible resource is free (assignment picks the winner, Spec 04).
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
