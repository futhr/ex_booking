# CLAUDE.md — ExBooking

Guidance for AI agents working in this repository. This file is the canonical
repo contract for architecture, hard rules, the documentation system, and the
quality gates. `AGENTS.md` is a short pointer that delegates here.

## What this library is

`ex_booking` is a pure, deterministic booking kernel: temporal math,
availability assembly, slot generation, conflict detection, assignment
strategies, and booking lifecycle decisions — as pure functions. It is
consumed by orchestration layers that own persistence, integrations, and
side effects.

## Hard Rules

1. **Purity**: nothing in `lib/` may touch a database, spawn/message processes,
   perform HTTP or file I/O, read the clock, or generate randomness. If you
   need `now`, it is a required caller input. If you need an effect, return an
   intent struct for the consumer to execute.
2. **Determinism**: identical inputs must always produce identical outputs,
   including ordering of returned lists (slots sort ascending by `start_at`,
   ties broken by resource id).
3. **Spec is source of truth**: `docs/specs/` defines the data model, API, and
   algorithms. Update the spec in the same change as the code. If you find a
   mismatch, surface it — do not silently pick one side.
4. **Slot interval is independent of duration** — never couple slot stepping
   to `duration_min`.
5. **No copyleft code**: the research corpus (`docs/research/R.01` §5) studied an
   AGPL-licensed scheduling product for concepts and test scenarios only; code
   from it — or any copyleft source — must never be copied or closely
   paraphrased into this MIT library.
6. **No new dependencies** without discussion. The runtime dep surface is
   deliberately tiny (`tz`, `nimble_options`).
7. Every public function needs a `@doc` and an `@spec` (Credo
   `Readability.Specs`); every module needs a `@moduledoc` (100% via `mix doctor`).

## Architecture

```text
consumer application (the orchestration layer)
  owns: persistence, state machine, APIs, auth/tenancy, jobs, webhooks,
        calendar/CRM/video/payment adapters, UI
        │  normalized structs in ──┐
        ▼                          │ decisions + intents out
              ExBooking (this library)
  owns: interval algebra, availability assembly, slot generation,
        conflict detection, assignment, lifecycle/policy evaluation
```

- `lib/ex_booking.ex` — public facade; keep it thin, delegate to submodules.
- `lib/ex_booking/` — one module per domain concept; main function at top of
  file, helpers below.

## Documentation System

- `docs/research/` — research notes (`R.NN-slug.md`) with sources, methodology,
  alternatives, and an explicit decision. Background only; do not encode
  behavior there.
- `docs/specs/` — normative specification (`SP.NN-slug.md`, numbered `00`–`07`).
- `docs/tasks/booking-tasks.md` — canonical checkbox task list.
- `docs/templates/` — base templates for new research, specs, and tasks.
- `notebooks/` — runnable Livebook tutorials, published to HexDocs (Livebooks
  group). Cells and saved outputs are executed and verified by
  `test/notebooks_test.exs`; after behavior changes run
  `mix run scripts/regen_notebook_outputs.exs` to refresh outputs. Each setup
  cell's version pin must match `mix.exs` (major.minor).
- `.claude/skills/` — repo-specific workflows for Claude Code.
- `.claude/standards/` — stable engineering standards (naming, quality gates).

Every accepted design gets a spec (`SP.NN`) and a task entry
(`docs/tasks/booking-tasks.md`) before broad implementation. Research notes link
to the task file rather than smuggling implementation tasks.

Project documents have no fixed token, word, character, page, line, file-size,
or diff-size budget. Size them to the evidence and decisions required for a
safe result. Split only for coherent ownership or lifecycle boundaries, never
merely because a document is long. Runtime limits and deliberately bounded
product-output contracts are separate and remain explicit.

## Quality Gates

`mix check` runs the full pipeline and must be green before you declare a task
done. The individual commands make failures easier to diagnose:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix deps.audit
mix dialyzer
mix doctor          # 100% moduledoc, ≥80% @spec coverage
mix docs
mix test --cover    # ≥95% line coverage (coveralls.json); test/support excluded
mix check           # runs all of the above (ex_check)
```

New algebra/slotting behavior needs StreamData property tests plus DST fixture
coverage (`Europe/Stockholm`, `America/New_York`), not just example tests.

## Commit Rules

Use Conventional Commits: `feat(scope):`, `fix(scope):`, `docs(scope):`,
`test(scope):`, `refactor(scope):`, `chore(scope):`. Commit or push only when
the user asks.
