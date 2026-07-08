defmodule ExBooking.Assignment do
  @moduledoc """
  Deterministic resource assignment.

  Assignment runs after availability has already established which resources
  can take the slot. Strategies use explicit fairness inputs from the caller,
  then fall back to resource id so ties are stable and replayable.

  A scorer may rank resources before the strategy key. The scorer receives the
  request routing context as opaque data; the kernel never inspects CRM, GTM,
  territory, or enrichment semantics.

  ## Example

      iex> slot = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])
      ...>
      ...> resources = [
      ...>   %ExBooking.Resource{id: "b", timezone: "Etc/UTC"},
      ...>   %ExBooking.Resource{id: "a", timezone: "Etc/UTC"}
      ...> ]
      ...>
      ...> {:ok, [winner]} = ExBooking.Assignment.assign(resources, slot, [])
      ...> winner.id
      "a"

  """

  alias ExBooking.Interval
  alias ExBooking.Resource

  @ranks_last 1_000_000_000

  @typedoc "Assignment strategy selector."
  @type strategy :: atom() | {atom(), keyword()}

  @typedoc "Opaque scoring hook over routing context."
  @type scorer :: (Resource.t(), map() -> number())

  @doc """
  Picks the resource(s) that take a booking for `slot`.

  Options: `:strategy` (default `:first_available`), `:scorer`,
  `:routing_context` (passed to the scorer), `:participants` (default `:one`),
  and `:capacity_required` (for `:pool`).

  ## Examples

      iex> resources = [
      ...>   %ExBooking.Resource{id: "b", timezone: "Etc/UTC"},
      ...>   %ExBooking.Resource{id: "a", timezone: "Etc/UTC"}
      ...> ]
      ...>
      ...> slot = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:30:00Z])
      ...>
      ...> {:ok, [winner]} =
      ...>   ExBooking.Assignment.assign(resources, slot, strategy: :first_available)
      ...>
      ...> winner.id
      "a"

  """
  @spec assign([Resource.t()], Interval.t(), keyword()) ::
          {:ok, [Resource.t()]} | {:error, :no_eligible_resource}
  def assign([], %Interval{} = _slot, _opts), do: {:error, :no_eligible_resource}

  def assign(resources, %Interval{} = _slot, opts) do
    strategy = Keyword.get(opts, :strategy, :first_available)
    scorer = Keyword.get(opts, :scorer)
    routing_context = Keyword.get(opts, :routing_context, %{})

    ranked = Enum.sort_by(resources, &sort_key(&1, strategy, scorer, routing_context))

    {:ok, select(ranked, opts)}
  end

  defp select(ranked, opts) do
    case Keyword.get(opts, :participants, :one) do
      :one -> Enum.take(ranked, 1)
      :collective -> ranked
      :pool -> Enum.take(ranked, Keyword.get(opts, :capacity_required, 1))
    end
  end

  defp sort_key(resource, strategy, scorer, routing_context) do
    {negated_score(resource, scorer, routing_context), strategy_key(resource, strategy),
     resource.id}
  end

  defp negated_score(_resource, nil, _routing_context), do: 0
  defp negated_score(resource, scorer, routing_context), do: -scorer.(resource, routing_context)

  defp strategy_key(_resource, :first_available), do: {0}

  defp strategy_key(resource, :round_robin),
    do: {assignments_count(resource), last_assigned_key(resource)}

  defp strategy_key(resource, :least_recently_booked), do: {last_assigned_key(resource)}
  defp strategy_key(resource, :weighted), do: {weighted_ratio(resource)}

  defp strategy_key(resource, :priority) do
    {-priority(resource), assignments_count(resource), last_assigned_key(resource)}
  end

  defp strategy_key(resource, {:owner_first, opts}) do
    owner_id = Keyword.fetch!(opts, :owner_id)
    fallback = Keyword.get(opts, :fallback, :round_robin)
    {owner_rank(resource, owner_id), strategy_key(resource, fallback)}
  end

  defp strategy_key(resource, {strategy, _opts}), do: strategy_key(resource, strategy)

  defp owner_rank(resource, owner_id), do: if(resource.id == owner_id, do: 0, else: 1)

  defp assignments_count(%Resource{fairness: nil}), do: @ranks_last

  defp assignments_count(%Resource{fairness: fairness}),
    do: Map.get(fairness, :assignments_count, @ranks_last)

  defp priority(%Resource{fairness: nil}), do: -@ranks_last
  defp priority(%Resource{fairness: fairness}), do: Map.get(fairness, :priority, -@ranks_last)

  defp weighted_ratio(%Resource{fairness: nil}), do: @ranks_last * 1.0

  defp weighted_ratio(%Resource{fairness: fairness}) do
    Map.get(fairness, :assignments_count, @ranks_last) / Map.get(fairness, :weight, 1.0)
  end

  defp last_assigned_key(%Resource{fairness: nil}), do: {0, 0}

  defp last_assigned_key(%Resource{fairness: fairness}) do
    case Map.get(fairness, :last_assigned_at) do
      nil -> {0, 0}
      %DateTime{} = last_assigned_at -> {1, DateTime.to_unix(last_assigned_at)}
    end
  end
end
