# ExBooking Docs Index

This is the entry point for understanding the `ex_booking` codebase. The repo is
a pure Elixir library: no Phoenix contexts, no Ash resources, no Ecto schemas,
no adapters, no processes, and no I/O. Consumers pass normalized data in and
execute returned intents outside this package.

## What Lives Here

```mermaid
flowchart TB
  facade["lib/ex_booking.ex\nPublic facade"]

  structs["Struct modules\nAvailabilityRule · Resource · MeetingType\nRequest · Decision · Hold · Event"]
  temporal["Temporal modules\nInterval · Schedule · Slotting"]
  availability["Availability modules\nAvailability · Policy"]
  assignment["Assignment module\nAssignment"]
  standards["Standards helpers\nRRule · ICalendar · JSCalendar"]

  facade --> structs
  facade --> temporal
  facade --> availability
  facade --> assignment
  facade --> standards
```

## Consumer Boundary

```mermaid
flowchart LR
  subgraph Consumer["Consumer application"]
    source["DB/API/UI/forms/providers"]
    normalize["Normalize into ExBooking structs"]
    execute["Execute returned intents"]
    persist["Persist booking state and events"]
  end

  subgraph Kernel["ex_booking"]
    slots["available_slots/4"]
    decide["decide/5"]
    lifecycle["reschedule/6 · cancel/3\nexpire_hold/2 · mark_no_show/3"]
    facts["Decision: reasons · alternatives\nevents · intents"]
  end

  source --> normalize --> slots --> decide --> facts --> execute --> persist
  normalize --> lifecycle --> facts
```

The kernel never fetches calendars, sends notifications, captures payments,
checks auth, starts jobs, or persists data. Those responsibilities belong to
consumer repos or adapter packages.

## Availability Flow

```mermaid
flowchart TD
  input["MeetingType + Resources + AvailabilityRules\nopts: now/from/until"]
  pair["Pair resources and rules positionally"]
  expand["Schedule.expand/3\nweekly windows + overrides + blackouts"]
  busy["Inflate and merge resource busy intervals"]
  subtract["Interval.subtract_all/2"]
  slot["Slotting.generate_all/4"]
  policy["Policy.violations/4"]
  combine["Participant mode\n:one · :collective · :pool"]
  output["Sorted available intervals"]

  input --> pair --> expand --> busy --> subtract --> slot --> policy --> combine --> output
```

Relevant specs:

- `docs/specs/SP.01-data-model.md`
- `docs/specs/SP.03-algorithms.md`

## Booking Decision Flow

```mermaid
sequenceDiagram
  participant App as Consumer app
  participant Facade as ExBooking
  participant Avail as Availability
  participant Assign as Assignment
  participant App2 as Consumer app

  App->>Facade: decide(request, meeting_type, resources, rules, opts)
  Facade->>Avail: eligible(request, meeting_type, resources, rules, now)
  alt slot invalid, busy, or policy rejected
    Avail-->>Facade: {:error, reasons}
    Facade-->>App: Decision(status, reasons, alternatives)
  else eligible resources
    Avail-->>Facade: {:ok, resources}
    Facade->>Assign: assign(resources, slot, strategy/scorer)
    Assign-->>Facade: {:ok, winners}
    Facade-->>App: Decision(status: :ok, events, intents)
    App->>App2: persist, create calendar event, notify, emit
  end
```

Relevant specs:

- `docs/specs/SP.02-public-api.md`
- `docs/specs/SP.04-assignment.md`
- `docs/specs/SP.05-lifecycle-and-events.md`

## Lifecycle Flow

```mermaid
stateDiagram-v2
  [*] --> offered
  offered --> held: decide/5 with hold
  offered --> confirmed: decide/5 without hold
  held --> confirmed: consumer confirms after revalidation
  held --> expired: expire_hold/2
  confirmed --> rescheduled: reschedule/6
  confirmed --> canceled: cancel/3
  confirmed --> no_show: mark_no_show/3
```

The consumer owns the persisted state machine. ExBooking only computes transition
facts, events, and intents.

## Standards Helpers

```mermaid
flowchart LR
  rrule["RRULE string or struct"] --> rrule_mod["ExBooking.RRule"] --> intervals["UTC intervals"]
  ics["ICS text with FREEBUSY"] --> ics_mod["ExBooking.ICalendar"] --> busy["busy intervals"]
  jscal["decoded JSCalendar map"] --> js_mod["ExBooking.JSCalendar"] --> busy
```

Relevant spec: `docs/specs/SP.06-standards-interop.md`.

## How To Continue Development

1. Read the relevant `SP.NN` spec for the module group being changed.
2. Add or update exactly one roadmap item in `docs/tasks/booking-tasks.md`.
3. Change code in the matching flat module under `lib/ex_booking/`.
4. Add module-level examples or properties under `test/`.
5. Run `mix check --no-retry` before committing.

Roadmap state belongs only in `docs/tasks/booking-tasks.md`; specs explain the
code as it exists and the contracts it must keep.

## Spec Index

- `SP.00` — kernel scope and ownership boundary.
- `SP.01` — public structs.
- `SP.02` — public facade API.
- `SP.03` — temporal availability algorithms.
- `SP.04` — assignment behavior.
- `SP.05` — lifecycle events and intents.
- `SP.06` — standards interop helpers.
- `SP.07` — validation gates and test rules.

## Research Index

- `docs/research/README.md` — research reading order and usage rules.
- `R.01` — booking-space and kernel rationale.
- `R.02` — standards interop spike.
- `R.03` — post-build kernel audit.
