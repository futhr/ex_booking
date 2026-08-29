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
- Write the smallest example, property, DST fixture, or characterization that proves the next
  behavior and run it against current code. It must fail at the intended assertion; a syntax,
  fixture, dependency, or harness failure is not RED. If it is already green, resolve whether the
  task is implemented or the proof is non-discriminating before editing.

## During

- Purity and determinism are non-negotiable: no clock, no I/O, no processes, no
  randomness. `now` is a caller input; effects are returned as intent structs.
- Slot interval is independent of `duration_min`.
- Reuse `ExBooking.Interval` algebra; do not re-derive overlap/subtract/merge.
- Keep `lib/ex_booking.ex` thin — delegate to the domain submodule.
- Every public function gets a `@doc`, a `@spec`, and a doctest.
- Update the cited `SP.NN` spec in the same change if behavior shifts.
- Add StreamData properties and DST fixtures for timezone-sensitive behavior.
- Make the smallest change that turns the same observed failing proof green. Never weaken, skip, or
  delete the proof to obtain GREEN.

## After

- Tick the task's `AC:` items in `docs/tasks/booking-tasks.md` and update the
  Progress Summary counts.
- Run the `done` skill; all gates must be clean.
- Record exact focused RED, focused GREEN, and final-gate output from the final working tree.
