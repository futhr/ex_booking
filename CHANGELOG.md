# Changelog

<!-- changelog -->

## [v0.1.0](https://github.com/futhr/ex_booking/compare/v0.1.0...v0.1.0) (unreleased)

### Features:

- Repo bootstrap: research doc, full specification (`docs/specs/SP.00-07`), tooling and CI.
- `ExBooking.Interval` — pure interval algebra (overlap, subtract, merge, clip, inflate).
- `ExBooking.Slotting` — slot-grid generation with slot interval independent of duration.
- Temporal core: DST-safe schedule expansion, availability assembly, conflict detection, and request validation.
- Assignment and policy: deterministic strategies, scoring hook, booking decisions, cancellation, and reschedule checks.
- Lifecycle and events: holds, reserve/release intents, canonical event emission, collective mode, and pool capacity.
- Standards helpers: dependency-free RRULE subset expansion, ICS free/busy normalization, JSCalendar busy mapping, and clock-aligned slots.
