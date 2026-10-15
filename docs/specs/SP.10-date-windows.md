---
ex_booking:
  id: "SP.10"
  title: "Explicit Date Windows"
  domain: booking
  status: normative
  priority: high
  created: "2026-10-14"
  updated: "2026-10-15"
  tags: ["calendar", "dates", "bounds"]
  depends_on: ["SP.01", "SP.02", "SP.07"]
---

# SP.10 - Explicit Date Windows

Select explicit calendar occurrences by their supplied dates. This pure API
does not manufacture midnight instants, durations or recurrence rules. Consumers
own source interpretation, ordering, identity, persistence and effects.

## Data model and API

DW-01. `%ExBooking.DatedOccurrence{on: Date.t(), starts_at: DateTime.t() | nil,
reference: String.t() | nil}` preserves a required ISO calendar date and an
optional independently supplied UTC instant. A supplied reference is nonempty
UTF-8 of at most 256 bytes; it is an opaque consumer coordinate, not authority.
Dates and instants have years 0000-9999 and valid native fields. Instants must
use `Etc/UTC`, `UTC` and zero offsets. Malformed structs reject before comparison.
The instant may fall on a different date; selection uses `on` alone.

```elixir
ExBooking.date_window(occurrences, from, to, opts \\ [])
ExBooking.CalendarWindow.select(occurrences, from, to, opts \\ [])
# {:ok, [ExBooking.DatedOccurrence.t()]} | {:error, reason}
```

DW-02. `from` and `to` are valid ISO Dates with `from <= to`. Both edges are
inclusive, including a single-day window. Return exactly entries satisfying
`from <= entry.on <= to`, in input order, with all values unchanged. Repeated
references remain repeated; uniqueness and sorting belong to the consumer.
Empty input is valid. No timezone database, clock or booking resource is needed.

## Bounds and errors

DW-03. Options are a closed keyword list without duplicate keys:

| Option | Default | Allowed values |
| --- | --- | --- |
| `input_limit` | 10000 | integer 1-100000 |
| `limit` | 1000 | integer 1-100000 |

Traverse at most `input_limit` entries and inspect the next list cell only to
detect excess input. Reject improper lists. Validate every admitted entry,
including entries outside the window. Exceeding an input or result bound returns
an error without partial results. There is no cursor or automatic limit increase.

DW-04. Errors contain closed reasons without foreign input values:

```text
{:invalid, :date_window, :options | :range | :occurrences | :occurrence}
{:limit, :date_window, :input | :output}
```

Invalid options precede invalid ranges; range checks precede traversal. During
traversal, input bound checks precede entry validation, which precedes output
counting. A malformed container is an occurrences error; a malformed entry is
an occurrence error. Identical inputs give identical results and errors.

## Compatibility and consumer boundary

DW-05. Existing interval, availability, lifecycle and original recurrence APIs
retain their contracts. A date is not an interval or a reservation. This API
performs no I/O, process work, clock reads, randomness or effect execution.
Passing a reference through it does not authenticate identity or authorize work.
Consumers pass only needed temporal coordinates and retain private/domain data
outside the kernel.

## Acceptance

| Case | Requirement | Independent observation |
| --- | --- | --- |
| DW-T1 | 01-02 | Leap-day and both inclusive edges survive; adjacent outside dates do not. |
| DW-T2 | 01-02 | A supplied instant on another day retains precision without changing date selection. |
| DW-T3 | 01-04 | Forged date/instant fields, invalid references, unknown/duplicate options and improper lists return closed errors without raising. |
| DW-T4 | 02-04 | Exact bounds, including 100000 entries/results, succeed; one excess entry or result fails without partial success. Error precedence holds at the output bound. Invalid out-of-window entries still reject. |
| DW-T5 | 02, 05 | Independent generated date lists across years 0000-9999 preserve input order and values; splitting an inclusive window at adjacent calendar days partitions the same result. |
| DW-T6 | 01-05 | An extracted archive consumer calls the public facade without a timezone database or additional runtime dependency. |

SP.07 owns full quality and archive checks. These cases are obligations until
observed results are recorded in the task list.

## Sources

[RFC 5545 Sections 3.3.4 and 3.3.5](https://www.rfc-editor.org/rfc/rfc5545.html)
distinguish DATE from DATE-TIME. This API uses native Elixir values and is not
an iCalendar wire parser. Read 2026-10-14.
