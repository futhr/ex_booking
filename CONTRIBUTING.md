# Contributing to ExBooking

Thanks for your interest in contributing!

## Ground rules

ExBooking is a **pure kernel**. Every contribution must preserve the design
contract:

1. **No side effects in `lib/`** — no database, no processes, no HTTP, no
   file I/O, no message sending. The kernel computes; consumers execute.
2. **Determinism** — same inputs produce same outputs. Never call
   `DateTime.utc_now/0`, `System.system_time/1`, or any randomness inside
   kernel code. `now` is always a caller-supplied input.
3. **Contract first** — behavior changes update the relevant contract, tests,
   and implementation together. If code and documentation disagree, one of them
   is a bug.

## Development

```sh
mix setup        # deps.get + deps.compile
mix check        # full pipeline: compile -Werr, format, credo, dialyzer,
                 # deps.audit, hex.audit, doctor, docs, test --cover, verify.package
```

All of `mix check` must pass before a PR is reviewed. Coverage is gated at 95%.
`mix verify.package` builds a temporary Hex archive, checks a fresh production
consumer and executes packaged notebook setup and examples. It needs registry
access (or populated Hex caches), `tar`, and the current `mix`/`elixir` on PATH.
Weekly CI runs both security audits. Dependency and GitHub Actions updates are
maintained manually and require the full gate.

## Testing

- Every public function gets doctests demonstrating the happy path.
- Interval algebra and slot generation are covered by StreamData property
  tests — new algebra operations need property tests, not just examples.
- Timezone-sensitive behavior must be exercised against the DST fixture
  corpus in `test/support/dst_fixtures.ex` (spring-forward and fall-back for
  at least `Europe/Stockholm` and `America/New_York`).

The September audit regressions are individually traceable in
[SP.07](docs/specs/SP.07-validation.md#audit-regression-traceability). Run all
of them with `mix test --only audit_finding`, or one finding with
`mix test --only audit_finding:A10`.

## Commit style

Conventional commits (`feat:`, `fix:`, `docs:`, `test:`, `chore:`); releases
and CHANGELOG are managed with `git_ops` (`mix release`).

## Releasing

Maintainers only: `mix release` bumps the version from the commit history,
updates `CHANGELOG.md`, and tags. Pushing the tag triggers the publish
workflow. The workflow accepts only the exact `v<project-version>` tag at the
triggering commit, runs the full quality gate on a clean tree, and builds a
validated Hex package before publishing. It then downloads the package from the
Hex registry, requires it to match the validated package byte for byte, and
attests that registry artifact. The Hex API key is available only to the publish
step.
