# ExBooking Research Index

Research documents explain why the kernel is shaped this way. They are
background material, not normative contracts. Normative behavior lives in
`docs/specs/`; executable roadmap state lives only in
`docs/tasks/booking-tasks.md`.

## Reading Order

```text
R.01  market/kernel rationale
R.02  standards interop spike
R.03  post-build kernel audit
```

## Documents

- `R.01-booking-space-and-kernel-rationale.md` — explains the market shape, why a
  pure kernel exists, what belongs in the kernel, and what belongs in consumers.
- `R.02-standards-spike.md` — records the RRULE/ICS/JSCalendar dependency and
  scope decision.
- `R.03-post-build-kernel-audit.md` — records the audit that added rejected-slot
  alternatives and pure lifecycle transition helpers while keeping orchestration
  concerns out.

## How To Use Research

Use research to understand tradeoffs and boundaries. Do not treat research files
as implementation checklists. When research changes accepted behavior, update the
matching `SP.NN` spec and add the executable task to
`docs/tasks/booking-tasks.md`.
