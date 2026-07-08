# Spec 04 — Assignment

**Status:** normative

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

All tie-breaks are total and deterministic (Spec 00).

## Scoring hook

GTM context (lead score, territory, campaign, account ownership) influences
assignment **only** through the opaque `:scorer` option:

```elixir
scorer :: (ExBooking.Resource.t(), routing_context :: map() -> number())
```

When present, eligible resources are ranked by score descending *before* the
strategy applies as tie-break. The kernel never inspects `routing_context` itself —
it flows from `Request.routing_context` through the hook and out into events
untouched. This is the boundary that keeps CRM/GTM semantics in the orchestration
layer (see R.01 §5.5).

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
meeting-limits-per-link, and distribution *credits* accounting live in
host apps/packs. They shape the inputs (`fairness`, `scorer`, pre-filtered pools),
never the kernel code.
