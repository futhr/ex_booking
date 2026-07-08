# Naming Standard

Stable vocabulary for `ex_booking`. Use these terms consistently in code, specs,
docs, and tests. Definitions are normative in `SP.01`.

## Canonical Terms

| Term | Meaning |
|---|---|
| Kernel | `ex_booking` itself — the pure decision engine. Never "engine", "service", or "server". |
| Consumer | The orchestration layer that owns persistence, side effects, and integrations. |
| Interval | Half-open `[start_at, end_at)` UTC `DateTime` range (`ExBooking.Interval`). |
| Availability rule | When a resource is offerable, before busy subtraction (`ExBooking.AvailabilityRule`). |
| Resource | A bookable person or pooled seat (`ExBooking.Resource`). Not "host", "user", or "agent" in code. |
| Meeting type | The bookable offering: duration, slot interval, buffers, participant mode (`ExBooking.MeetingType`). |
| Slot interval | The grid step (`slot_interval_min`). **Independent of `duration_min`.** Never "slot duration". |
| Duration | Meeting length (`duration_min`). Distinct from slot interval. |
| Buffer | Padding around busy time (`before_min`/`after_min`). Inflates busy, not slots (`SP.03` §3.5). |
| Hold | A temporary reservation as data (`ExBooking.Hold`); the kernel never expires it. |
| Decision | The kernel's answer carrying status, slot, resources, reasons, events, intents. |
| Intent | A described side effect for the consumer to execute (`:reserve`, `:emit`, …). Never performed by the kernel. |
| Event | A canonical lifecycle event (`:booking_confirmed`, …); the cross-system contract. |
| Scoring hook | The opaque `:scorer` through which CRM/GTM context influences assignment. |
| Routing context | Opaque consumer map; never interpreted by the kernel, round-tripped into events. |

## Avoid

- "slot duration" (conflates slot interval and duration).
- "engine"/"service"/"server" for the kernel.
- "host"/"user" in code where the type is `Resource`.
- Naming any private consumer application or a commercial vendor product.
- Coupling grid stepping to duration anywhere.
