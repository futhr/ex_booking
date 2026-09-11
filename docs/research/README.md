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
R.04  availability performance profile
R.05  September audit
R.06  production hardening and consumer evidence
```

## Documents

- `R.01-booking-space-and-kernel-rationale.md` — explains the market shape, why a
  pure kernel exists, what belongs in the kernel, and what belongs in consumers.
- `R.02-standards-spike.md` — records the RRULE/ICS/JSCalendar dependency and
  scope decision.
- `R.03-post-build-kernel-audit.md` — records the audit that added rejected-slot
  alternatives and pure lifecycle transition helpers while keeping orchestration
  concerns out.
- `R.04-availability-performance-profile.md` — records measured availability
  costs and the earlier optimization decisions.
- `R.05-september-audit.md` — records the preceding correctness and maintenance
  audit; R.06 continues from the resulting 0.2.1 source.
- [R.06-production-hardening.md](R.06-production-hardening.md) — records boundary
  reproductions, fixes, dependency/runtime consumers and comparable measurements.

## How To Use Research

Use research to understand tradeoffs and boundaries. Do not treat research files
as implementation checklists. When research changes accepted behavior, update the
matching `SP.NN` spec and add the executable task to
`docs/tasks/booking-tasks.md`.
