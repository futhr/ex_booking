# Changelog

<!-- changelog -->

## [v0.1.0](https://github.com/futhr/ex_booking/compare/v0.1.0...v0.1.0) (unreleased)

### Features:

- Repo bootstrap: research doc, full specification (`docs/specs/SP.00-07`), tooling and CI.
- `ExBooking.Interval` — pure interval algebra (overlap, subtract, merge, clip, inflate).
- `ExBooking.Slotting` — slot-grid generation with slot interval independent of duration.
- Struct skeletons and typespecs for the full public surface; unimplemented calls return `{:error, :not_implemented}`.
