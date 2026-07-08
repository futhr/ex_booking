---
ex_booking:
  id: "SP.04"
  title: "Assignment"
  domain: booking
  status: normative
  priority: high
  created: "2026-07-08"
  updated: "2026-07-08"
  tags: ["assignment", "fairness", "round-robin", "scoring-hook"]
  depends_on: ["R.01", "SP.01"]
---

# SP.04 — Assignment

Assignment answers: *given resources free for a slot, who takes the booking?*
Strategies are pure functions over explicit inputs — the kernel holds no counters,
no history, no CRM knowledge. Consumers maintain `Resource.fairness` and pass it in.

## Strategies

Selected via the `:strategy` option (`atom()` or `{atom(), keyword()}`):

| Strategy | Selection rule | Tie-break |
|---|---|---|
| `:first_available` (default) | First free resource | resource id asc |
| `:round_robin` | Lowest `fairness.assignments_count` | earliest `last_assigned_at`, then id |
| `:least_recently_booked` | Earliest `fairness.last_assigned_at` (nil = never = first) | id |
| `:weighted` | Lowest `assignments_count / weight` ratio | id |
| `:priority` | Highest `fairness.priority`, free wins | round_robin among equals |
| `:owner_first` | `{: owner_first, owner_id: id}` — the owner if free, else fall back to a configurable strategy (default `:round_robin`) over the pool | per fallback |
| `:collective` | All required resources (participants `:collective`); not a choice, a constraint | — |

All tie-breaks are total and deterministic (SP.00).

## Scoring hook

GTM context (lead score, territory, campaign, account ownership) influences
assignment **only** through the opaque `:scorer` option:

```elixir
scorer :: (ExBooking.Resource.t(), routing_context :: map() -> number())
```

The kernel never inspects `routing_context` itself — it flows from
`Request.routing_context` through the hook and out into events untouched. This is
the boundary that keeps CRM/GTM semantics in the orchestration layer (R.01 §6.5).

### Selection algorithm (normative)

Given eligible (free) resources, the winner is chosen by this exact sort:

```text
select(resources, slot, opts) =
  scored   = if opts[:scorer], do: score each resource with
             scorer.(resource, routing_context), else: all score 0
  ranked   = sort resources by, in order:
               1. score                      descending
               2. strategy key (table above) per-strategy direction
               3. strategy tie-break         (table above)
               4. resource id                ascending (final, total order)
  take 1 for :one · all required for :collective ·
  capacity_required for :pool (from the front of the ranking)
```

Missing fairness data ranks last within its comparison (a `nil`
`last_assigned_at` means "never assigned" and ranks *first* for
`:least_recently_booked` — the one exception, stated in the table). All
comparisons are stable; the final resource-id comparison guarantees a total,
deterministic order (spec 00).

## Contract

```elixir
@spec assign([Resource.t()], Interval.t(), keyword()) ::
        {:ok, [Resource.t()]} | {:error, :no_eligible_resource}
```

- Input resources are pre-filtered for freeness by the caller or by `decide/5`.
- Returns a list: one resource for `:one` mode, all required for `:collective`,
  `capacity_required` resources for `:pool`.
- An empty eligible set returns `{:error, :no_eligible_resource}`; `decide/5`
  translates that into `Decision{status: :needs_routing}` so orchestration can
  apply fallback pools.

## Explicitly out of kernel

Territory mapping, SDR→AE handoff rules, enrichment, spam screening,
meeting-limits-per-link, and distribution *credits* accounting live in the
consuming orchestration layer. They shape the inputs (`fairness`, `scorer`,
pre-filtered pools), never the kernel code.
