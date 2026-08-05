---
name: booking-implement
description: Implement an ExBooking task from docs/tasks/booking-tasks.md or docs/specs. Use for kernel code changes in temporal math, availability, slotting, conflict detection, assignment, policy, or lifecycle.
disable-model-invocation: true
allowed-tools: Read, Glob, Grep, Edit, Write, Bash(mix *), Bash(rg *), Bash(git *)
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
