---
name: booking-implement
description: "Apply automatically when implementing a bounded ExBooking task that changes temporal math, availability, slot generation, conflict detection, assignment, policy, or lifecycle code. Follow the linked task and normative spec, preserve time-zone, DST, overlap, concurrency, public API, and Hex-consumer invariants, and report unavailable proof explicitly."
---

# Booking Implement

Implement a task from `docs/tasks/booking-tasks.md`, driven by the normative
spec it cites.

## Before

- Read `CLAUDE.md` and the cited `SP.NN` section in full.
- Confirm the task's dependencies (earlier milestone tasks) are done.
- Check `docs/specs/SP.02` for the error vocabulary and option contract.

## During

- Purity and determinism are non-negotiable: no clock, no I/O, no processes, no
  randomness. `now` is a caller input; effects are returned as intent structs.
- Slot interval is independent of `duration_min`.
- Reuse `ExBooking.Interval` algebra; do not re-derive overlap/subtract/merge.
- Keep `lib/ex_booking.ex` thin — delegate to the domain submodule.
- Every public function gets a `@doc`, a `@spec`, and a doctest.
- Update the cited `SP.NN` spec in the same change if behavior shifts.
- Add StreamData properties and DST fixtures for timezone-sensitive behavior.

## After

- Tick the task's `AC:` items in `docs/tasks/booking-tasks.md` and update the
  Progress Summary counts.
- Run the `done` skill; all gates must be clean.
