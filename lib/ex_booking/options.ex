defmodule ExBooking.Options do
  @moduledoc "Shared option validation for the booking kernel's public boundaries."

  alias ExBooking.Temporal

  @doc """
  Validates keyword shape, schema, and common identity/context fields.

  ## Examples

      iex> ExBooking.Options.validate(:bad, [])
      {:error, {:invalid, :opts, :not_a_keyword_list}}
  """
  @spec validate(term(), NimbleOptions.t() | keyword()) :: {:ok, keyword()} | {:error, term()}
  def validate(opts, schema) when is_list(opts) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, {:invalid, :opts, :not_a_keyword_list}}

      length(Enum.uniq(Keyword.keys(opts))) != length(opts) ->
        {:error, {:invalid, :opts, :duplicate_keys}}

      true ->
        validate_schema(opts, schema)
    end
  end

  def validate(_, _), do: {:error, {:invalid, :opts, :not_a_keyword_list}}

  defp validate_schema(opts, schema) do
    with {:ok, opts} <- validate_fields(opts) do
      case NimbleOptions.validate(opts, schema) do
        {:ok, validated} -> {:ok, validated}
        {:error, error} -> {:error, {:invalid, :opts, Exception.message(error)}}
      end
    end
  end

  defp validate_fields(opts) do
    case Enum.find(opts, &invalid_field?/1) do
      nil -> {:ok, opts}
      {field, value} -> {:error, {:invalid, field, value}}
    end
  end

  defp invalid_field?({:resource_ids, ids}) when is_list(ids), do: Enum.any?(ids, &(&1 == ""))
  defp invalid_field?({:release_hold_id, id}), do: id == ""
  defp invalid_field?({:routing_context, context}), do: is_struct(context)

  defp invalid_field?({key, %DateTime{} = value}) when key in [:now, :from, :until],
    do: not Temporal.datetime?(value)

  defp invalid_field?(_), do: false

  @doc """
  Requires paired, increasing horizon endpoints when a horizon is supplied.

  ## Examples

      iex> ExBooking.Options.validate_horizon([], :optional)
      :ok
  """
  @spec validate_horizon(term(), :required | :optional) :: :ok | {:error, term()}
  def validate_horizon(opts, requirement) when is_list(opts) do
    if Keyword.keyword?(opts) do
      with {:ok, opts} <- validate_fields(opts) do
        validate_keyword_horizon(opts, requirement)
      end
    else
      {:error, {:invalid, :opts, :not_a_keyword_list}}
    end
  end

  def validate_horizon(_, _), do: {:error, {:invalid, :opts, :not_a_keyword_list}}

  defp validate_keyword_horizon(opts, requirement) do
    from? = Keyword.has_key?(opts, :from)
    until? = Keyword.has_key?(opts, :until)

    case {from?, until?, Keyword.get(opts, :from), Keyword.get(opts, :until), requirement} do
      {false, false, _, _, :optional} ->
        :ok

      {true, true, %DateTime{} = from, %DateTime{} = until, _} ->
        if DateTime.compare(from, until) == :lt,
          do: :ok,
          else: {:error, {:invalid, :horizon, :not_increasing}}

      {true, true, _, _, _} ->
        :ok

      _ ->
        {:error, {:invalid, :horizon, :requires_from_and_until}}
    end
  end
end
