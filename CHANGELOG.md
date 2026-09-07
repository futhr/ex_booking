# Changelog

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://www.conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.2.1](https://github.com/futhr/ex_booking/compare/v0.2.0...v0.2.1) (2026-09-07)




### Bug Fixes:

* capacity: account for peak concurrent reservations by Tobias Bohwalli

* icalendar: reject empty free-busy periods by Tobias Bohwalli

* schedule: remove overnight spill on closed dates by Tobias Bohwalli

* validation: enforce consistent public option boundaries by Tobias Bohwalli

* assignment: compare exact weights and precise timestamps by Tobias Bohwalli

* assignment: rank missing fairness without numeric sentinels by Tobias Bohwalli

* time: compare and deduplicate slots by exact instants by Tobias Bohwalli

* policy: preserve precision at lead-time boundaries by Tobias Bohwalli

* rrule: skip DST gaps and reject conflicting bounds by Tobias Bohwalli

* rrule: anchor weekly intervals to Monday by Tobias Bohwalli

* decisions: retain request constraints in alternatives by Tobias Bohwalli

* jscalendar: reject unsupported recurrence before filtering by Tobias Bohwalli

* rrule: bound traversal and jump between active weeks by Tobias Bohwalli

* availability: preserve collective participant requirements by Tobias Bohwalli

* resources: reject duplicate identities before allocation by Tobias Bohwalli

* security: update Mint and enforce Hex advisory audit by Tobias Bohwalli

* types: resolve membership dialyzer findings by futhr

### Performance Improvements:

* interval: subtract normalized sets with a linear sweep by Tobias Bohwalli

## Unreleased

### Changed

- Weekly recurrence uses Monday-anchored intervals and bounded traversal.
  Invalid local times are skipped without consuming COUNT; COUNT and UNTIL
  together now return an error.
- Duplicate resource IDs, malformed options, unsupported JSCalendar recurrence
  fields and empty FREEBUSY periods now return explicit errors.
- Closed-day overrides remove inbound overnight availability. Collective
  preferences retain all required participants, and alternatives preserve
  request preferences.
- Lead-time checks, slot deduplication, hold matching and assignment ordering
  preserve microsecond precision. Missing fairness ranks explicitly, and
  weighted assignment supports arbitrarily large integer counters.
- Interval subtraction normalizes both sets and uses a linear sweep after
  sorting. Pool capacity uses peak simultaneous reservation consumption.
- Shared validation removes redundant work and unreachable fallback branches;
  public types describe supported strategies and partial fairness maps.

### Maintenance

- Update Mint to 1.10.0, ExDoc to 0.40.4 and Req to 0.7.4; add Hex registry
  advisory checks alongside the existing dependency audit.
- Update pinned checkout/cache actions and add weekly security checks and
  dependency update proposals.
- Expand behavioral properties, package notebook sources, verify extracted Hex
  archives in fresh consumers, execute notebook setup cells, and separate smoke
  benchmarks from full performance measurements.

These unreleased changes alter recurrence results and malformed-input handling.
Consumers should review those behavior changes before upgrading.


## [v0.2.0](https://github.com/futhr/ex_booking/compare/v0.1.0...v0.2.0) (2026-08-24)




### Features:

* guidance: add terse prose skills by futhr

* guidance: align automatic repository skills by Tobias Bohwalli

### Bug Fixes:

* release: manage Livebook version pins with GitOps by futhr

## [v0.1.0](https://github.com/futhr/ex_booking/releases/tag/v0.1.0) (2026-08-18)

### Features:

* kernel: complete booking lifecycle contracts by futhr

* lifecycle: close research audit gaps by futhr

* jscalendar: map busy events by futhr

* ics: import free busy intervals by futhr

* rrule: expand recurring intervals by futhr

* slotting: align slots to clock boundaries by futhr

* booking: add assignment decisions by futhr

* availability: build slot assembly by futhr

* model: add booking domain structs by futhr

### Bug Fixes:

* release: close readiness gaps by futhr

* types: narrow the test builder contract by futhr
