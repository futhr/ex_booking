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

  @base_strategies [
    :first_available,
    :round_robin,
    :least_recently_booked,
    :weighted,
    :priority
  ]
  @fairness_fields [:assignments_count, :last_assigned_at, :weight, :priority]

  @doc """
  Validates a strategy and any fairness inputs it consumes.

  Validation is separate from selection so callers can reject malformed input
  before performing availability work.
  """
  @spec validate([Resource.t()], keyword()) ::
          :ok | {:error, {:invalid, :opts | :strategy | :resource_weight, term()}}
  def validate(resources, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      validate_keyword_options(resources, opts)
    else
      {:error, {:invalid, :opts, :not_a_keyword_list}}
    end
  end

  def validate(_, _), do: {:error, {:invalid, :opts, :not_a_keyword_list}}

  defp validate_keyword_options(resources, opts) do
    strategy = Keyword.get(opts, :strategy, :first_available)

    with :ok <- validate_strategy(strategy),
         :ok <- validate_resources(resources, strategy),
         :ok <- validate_scorer(Keyword.get(opts, :scorer)) do
      validate_weights(resources, strategy)
    end
  end

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
          {:ok, [Resource.t()]}
          | {:error, :no_eligible_resource | {:invalid, atom(), term()}}
  def assign(resources, %Interval{} = slot, opts) do
    with :ok <- Interval.validate(slot),
         :ok <- validate(resources, opts) do
      assign_valid(resources, slot, opts)
    end
  end

  defp assign_valid([], %Interval{}, _), do: {:error, :no_eligible_resource}

  defp assign_valid(resources, %Interval{}, opts) do
    strategy = Keyword.get(opts, :strategy, :first_available)
    scorer = Keyword.get(opts, :scorer)
    routing_context = Keyword.get(opts, :routing_context, %{})

    with {:ok, scored} <- score_resources(resources, scorer, routing_context) do
      ranked =
        Enum.sort_by(scored, fn {resource, score} -> sort_key(resource, strategy, score) end)

      case select(Enum.map(ranked, &elem(&1, 0)), opts) do
        [] -> {:error, :no_eligible_resource}
        selected -> {:ok, selected}
      end
    end
  end

  defp validate_resources(resources, strategy) when is_list(resources) do
    resources
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn
      {%Resource{id: id, fairness: fairness}, _}, :ok when is_binary(id) and id != "" ->
        case validate_fairness(id, fairness, strategy) do
          :ok -> {:cont, :ok}
          {:error, _} = error -> {:halt, error}
        end

      {%Resource{id: id}, _}, :ok ->
        {:halt, {:error, {:invalid, :resource_id, id}}}

      {resource, index}, :ok ->
        {:halt, {:error, {:invalid, :resources, {index, resource}}}}
    end)
  end

  defp validate_resources(resources, _), do: {:error, {:invalid, :resources, resources}}

  defp validate_fairness(_, nil, _), do: :ok

  defp validate_fairness(id, fairness, strategy)
       when is_map(fairness) and not is_struct(fairness) do
    case Enum.find(fairness, &invalid_fairness?/1) do
      nil ->
        :ok

      {:weight, weight} = invalid ->
        fairness_weight_error(id, weight, invalid, strategy)

      invalid ->
        {:error, {:invalid, :resource_fairness, {id, invalid}}}
    end
  end

  defp validate_fairness(id, fairness, _),
    do: {:error, {:invalid, :resource_fairness, {id, fairness}}}

  defp invalid_fairness?({key, _}) when key not in @fairness_fields, do: true
  defp invalid_fairness?({:assignments_count, value}), do: not is_integer(value) or value < 0

  defp invalid_fairness?({:last_assigned_at, value}),
    do: value != nil and not is_struct(value, DateTime)

  defp invalid_fairness?({:weight, value}), do: not is_number(value) or value <= 0
  defp invalid_fairness?({:priority, value}), do: not is_integer(value)

  defp fairness_weight_error(id, weight, invalid, strategy) do
    if weighted?(strategy),
      do: {:error, {:invalid, :resource_weight, {id, weight}}},
      else: {:error, {:invalid, :resource_fairness, {id, invalid}}}
  end

  defp validate_scorer(nil), do: :ok
  defp validate_scorer(scorer) when is_function(scorer, 2), do: :ok
  defp validate_scorer(scorer), do: {:error, {:invalid, :scorer, scorer}}

  defp validate_strategy(strategy) when strategy in @base_strategies, do: :ok

  defp validate_strategy({:owner_first, opts} = strategy) when is_list(opts) do
    owner_id = Keyword.get(opts, :owner_id)
    fallback = Keyword.get(opts, :fallback, :round_robin)

    if Keyword.keyword?(opts) and Enum.uniq(Keyword.keys(opts)) == Keyword.keys(opts) and
         Enum.all?(Keyword.keys(opts), &(&1 in [:owner_id, :fallback])) and
         is_binary(owner_id) and owner_id != "" and fallback in @base_strategies do
      :ok
    else
      {:error, {:invalid, :strategy, strategy}}
    end
  end

  defp validate_strategy(strategy), do: {:error, {:invalid, :strategy, strategy}}

  defp validate_weights(resources, strategy) do
    if weighted?(strategy) do
      case Enum.find_value(resources, &invalid_weight/1) do
        nil -> :ok
        {id, weight} -> {:error, {:invalid, :resource_weight, {id, weight}}}
      end
    else
      :ok
    end
  end

  defp weighted?(:weighted), do: true

  defp weighted?({:owner_first, opts}),
    do: Keyword.get(opts, :fallback, :round_robin) == :weighted

  defp weighted?(_), do: false

  defp invalid_weight(%Resource{id: id, fairness: fairness}) when is_map(fairness) do
    weight = Map.get(fairness, :weight, 1.0)
    if is_number(weight) and weight > 0, do: nil, else: {id, weight}
  end

  defp invalid_weight(%Resource{fairness: nil}), do: nil
  defp invalid_weight(%Resource{id: id, fairness: fairness}), do: {id, fairness}

  defp select(ranked, opts) do
    case Keyword.get(opts, :participants, :one) do
      :one -> Enum.take(ranked, 1)
      :collective -> ranked
      :pool -> take_capacity(ranked, Keyword.get(opts, :capacity_required, 1))
    end
  end

  defp take_capacity(resources, required) when is_integer(required) and required > 0 do
    {selected, remaining} =
      Enum.reduce_while(resources, {[], required}, &take_resource/2)

    if remaining == 0, do: Enum.reverse(selected), else: []
  end

  defp take_capacity(_, _), do: []

  defp take_resource(%Resource{capacity: capacity} = resource, {selected, remaining})
       when is_integer(capacity) and capacity > 0 do
    next = {[resource | selected], max(remaining - capacity, 0)}
    if elem(next, 1) == 0, do: {:halt, next}, else: {:cont, next}
  end

  defp take_resource(_, acc), do: {:cont, acc}

  defp score_resources(resources, scorer, routing_context) do
    result =
      Enum.reduce_while(resources, {:ok, []}, fn resource, {:ok, acc} ->
        case score(resource, scorer, routing_context) do
          {:ok, value} -> {:cont, {:ok, [{resource, value} | acc]}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    case result do
      {:ok, scored} -> {:ok, Enum.reverse(scored)}
      error -> error
    end
  end

  defp score(_, nil, _), do: {:ok, 0}

  defp score(resource, scorer, routing_context) do
    try do
      case scorer.(resource, routing_context) do
        value when is_number(value) -> {:ok, value}
        value -> {:error, {:invalid, :scorer_result, {resource.id, value}}}
      end
    rescue
      _ -> {:error, {:invalid, :scorer_result, {resource.id, :raised}}}
    catch
      _, _ -> {:error, {:invalid, :scorer_result, {resource.id, :raised}}}
    end
  end

  defp sort_key(resource, strategy, score) do
    {-score, strategy_key(resource, strategy), resource.id}
  end

  defp strategy_key(_, :first_available), do: {0}

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

  defp strategy_key(resource, {strategy, _}), do: strategy_key(resource, strategy)

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
