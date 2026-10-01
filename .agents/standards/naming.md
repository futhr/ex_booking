# Naming Standard

Stable vocabulary for `ex_booking`. Use these terms consistently in code, specs,
docs, and tests. Definitions are normative in
[SP.01](../../docs/specs/SP.01-data-model.md).

## Canonical Terms

| Term | Meaning |
|---|---|
| Kernel | `ex_booking` itself — the pure booking library. Use "kernel" rather than "engine", "service", or "server". |
| Consumer | The orchestration layer that owns persistence, side effects, and integrations. |
| Interval | Half-open `[start_at, end_at)` UTC `DateTime` range (`ExBooking.Interval`). |
| Availability rule | When a resource is offerable, before busy subtraction (`ExBooking.AvailabilityRule`). |
| Resource | A bookable person or pooled seat (`ExBooking.Resource`). Not "host", "user", or "agent" in code. |
| Meeting type | The bookable offering: duration, slot interval, buffers, participant mode (`ExBooking.MeetingType`). |
| Slot interval | The grid step (`slot_interval_min`). **Independent of `duration_min`.** Never "slot duration". |
| Duration | Meeting length (`duration_min`). Distinct from slot interval. |
| Buffer | Padding for busy/request overlap checks (`before_min`/`after_min`). See [SP.03](../../docs/specs/SP.03-algorithms.md) for assembly/validation equivalence; slot output retains meeting duration. |
| Reservation | Caller-supplied interval and seat consumption (`ExBooking.Reservation`), distinct from generic busy time. |
| Hold | A temporary reservation as data (`ExBooking.Hold`); expiry decisions use caller-supplied time and consumers apply the result. |
| Decision | The kernel's answer carrying status, slot, resources, reasons, events, intents. |
| Intent | A tagged tuple describing a side effect for the consumer to execute (`ExBooking.Decision.intent()`). |
| Event | A canonical lifecycle event (`:booking_confirmed`, …); the cross-system contract. |
| Scoring hook | The opaque `:scorer` through which CRM/GTM context influences assignment. |
| Routing context | Opaque consumer map; never interpreted by the kernel, round-tripped into events. |

## Avoid

- "slot duration" (conflates slot interval and duration).
- "engine"/"service"/"server" for the kernel.
- "host"/"user" in code where the type is `Resource`.
- Naming any private consumer application or a commercial vendor product.
- Coupling grid stepping to duration anywhere.
