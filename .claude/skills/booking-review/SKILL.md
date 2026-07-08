---
name: booking-review
description: Review ExBooking changes for purity, determinism, DST correctness, tests, docs, and quality-gate risk. Use when the user asks for review, audit, bug hunt, coverage review, or architecture review.
allowed-tools: Bash(rg *), Bash(mix *), Bash(git *)
---

# Booking Review

Ordered review checklist for a kernel change.

## Checklist

1. **Purity** — no clock reads (`DateTime.utc_now`, `Date.utc_today`), no I/O,
   no process/message calls, no `:rand`/randomness in `lib/`. `now` is always a
   caller input.
2. **Determinism** — returned lists are sorted deterministically (slots by
   `start_at`, tie-break resource id); no reliance on map ordering.
3. **Slot interval ≠ duration** — grid stepping is `slot_interval_min ||
   duration_min`, never coupled to duration.
4. **DST** — timezone-sensitive code resolves ambiguous → first occurrence,
   gap → snap forward, with `Europe/Stockholm` + `America/New_York` fixtures.
5. **Spec alignment** — behavior matches the cited `SP.NN` section; the spec was
   updated in the same change if it shifted.
6. **Error vocabulary** — tagged tuples match `SP.02`; `{:error, _}` reserved
   for malformed input, not business conditions.
7. **Docs/tests** — every public function has `@doc`, `@spec`, doctest; property
   and example coverage present; `mix doctor` and coverage gates would pass.

## Extra Checks

- No new dependencies without discussion.
- No copyleft code copied or paraphrased (`R.01` §5).
- `docs/tasks/booking-tasks.md` progress reflects the change.
