# ExBooking Agent Contract

Read this file before working in the repository. It is the canonical contract
for repository architecture, agent workflows, and delivery requirements.
Behavior is defined by the normative specifications in `docs/specs/`.

## Kernel and consumer boundary

`ex_booking` is a pure, deterministic Elixir booking kernel. It computes temporal
math, availability, slots, conflicts, assignment, policy, and lifecycle decisions
from caller-supplied data. Consumer applications own persistence, authentication,
tenancy, state machines, jobs, integrations, UI, and execution of returned intents.

- `lib/ex_booking.ex` is the public facade. Keep it thin and delegate to the
  owning domain module under `lib/ex_booking/`.
- Reuse `ExBooking.Interval` for interval algebra. Put the main operation before
  private helpers and use the vocabulary in
  [.agents/standards/naming.md](.agents/standards/naming.md).
- `lib/` must not perform database, HTTP, or file I/O; spawn or message processes;
  read the clock; or generate randomness. Require `now` as a caller input when
  needed, and describe effects through `ExBooking.Decision.intent()` values.
  Do not introduce an application callback or hidden configuration dependencies.
- Identical inputs must produce identical outputs, including list ordering.
  Slots sort by start instant; assignment strategies use the specified stable
  tie-breaks. Do not rely on map iteration order.
- Intervals are half-open UTC ranges. An explicit slot interval controls the
  grid independently of duration; the default when it is absent is defined in
  `SP.03`. Apply each mechanism's specified DST policy: availability windows and
  recurrence have different gap handling.
- Availability and decisions use supplied snapshots. Consumers must revalidate
  and reserve atomically; the kernel cannot guarantee persistence concurrency.
- Update the owning spec, tests, and task checklist with behavior changes.
  Surface spec/code disagreements and resolve them explicitly.
- Discuss new dependencies before adding them. Runtime dependencies are
  deliberately limited to `tz` and `nimble_options`.
- Never copy or closely paraphrase copyleft implementation into this MIT library.
  External designs may inform concepts and test cases; see
  [R.01 §5](docs/research/R.01-booking-space-and-kernel-rationale.md#5-the-closest-oss-reference-and-why-it-is-not-the-base).
- Every module needs `@moduledoc`; every public function needs `@doc`, `@spec`,
  and a runnable doctest demonstrating its behavior.

## Documentation ownership

- The [spec index](docs/README.md#spec-index) maps `SP.00` through `SP.07` to
  scope, structs, public API, algorithms, assignment, lifecycle, standards
  interop, and validation respectively. Read the matching files and sections.
- `docs/tasks/booking-tasks.md` is the single roadmap and acceptance checklist.
  Accepted designs need a spec and task entry before broad implementation.
- `docs/research/` holds background evidence and decisions, using `R.NN-slug.md`.
  It does not define behavior or duplicate implementation task lists.
- `docs/templates/` owns the formats for project research, specs, and tasks.
  Use a template only when creating the corresponding document.
- `notebooks/` contains executable Livebook tutorials published in HexDocs.
  `test/notebooks_test.exs` checks examples and saved outputs;
  `mix verify.package` executes packaged setup cells and examples in fresh
  Elixir processes. After a behavior change that affects outputs, run
  `mix run scripts/regen_notebook_outputs.exs`. Setup version pins must match
  the major/minor version in `mix.exs`.

Write precise, evidence-scoped prose. Preserve identifiers, commands, measured
values, and domain terms. Explain concrete behavior and caller ownership; remove
filler, marketing claims, and comments that only restate code. Distinguish
specified behavior, observed behavior, proposals, and inference. Never present
planned checks, coverage percentages, or text searches as semantic proof.
Documents have no fixed size budget; split only for coherent ownership or use.

## Skill selection and discovery

Canonical skills are tracked under `.agents/skills/`. The AI selects and reads
matching `SKILL.md` files from their descriptions as the task, changed mechanism,
or delivery stage requires. Users do not invoke skills or choose slash commands.
Clients without native discovery must inspect the descriptions and read the
matching files themselves. Load supporting material only when relevant.

Codex discovers `.agents/skills/` natively. Claude Code discovers individual
skill directories under `.claude/skills/`; local links use
`../../.agents/skills/<name>` as their target. Keep `.claude/` entirely ignored
and preserve unrelated local entries and settings. When preparing a checkout,
create missing individual directory links for canonical skills and repair
repository-owned dangling links without replacing local entries. Do not link
the whole skills directory or create duplicate aliases.

Claude Code 2.1.277 and later can load `AGENTS.md` natively. Clients whose version
or local configuration does not load it must read it explicitly. Keep automatic
skill selection enabled; retained skills use `user-invocable: false` to keep
Claude's skill menu out of the workflow.

## Validation and handoff

Use the verification skill at delivery. For application changes, run focused
behavioral checks and then `mix check --no-retry`, the full gate configured in
`.check.exs`. Clients without native skill discovery must also attempt this gate
before handoff. Its individual checks and test obligations are defined in
[SP.07](docs/specs/SP.07-validation.md), with thresholds enforced by
`.doctor.exs`, `coveralls.json`, and `.credo.exs`.

New algebra and slotting behavior needs StreamData properties; timezone changes
need Stockholm and New York DST fixtures. A syntax, fixture, dependency, or
harness failure is not evidence that an assertion detects a behavioral fault.
Do not weaken tests, add coverage padding, or hide failures with exclusions.

For guidance-only changes, check skill metadata, references, Git tracking and
ignore boundaries, and local discovery links. Run existing tools appropriate to
the affected surface. Report commands actually run, their outcomes, and every
failed, skipped, blocked, or hosted-only check. A blocked gate remains unverified;
do not install tools or dependencies outside the authorized scope to satisfy it.
Local checks cannot certify hosted CI, publication, provenance, or a real
downstream application's behavior.

Preserve unrelated edits and local configuration. Use Conventional Commits
(`feat`, `fix`, `docs`, `test`, `refactor`, `chore`, with scope when useful).
Commit, push, publish, or release only when the user requests it; existing
authorization remains sufficient. Report any validation limitation with the
handoff or authorized commit. Do not add generated-by or co-author markers.
