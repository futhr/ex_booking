defmodule ExBooking.Interval do
  @moduledoc """
  A half-open time interval `[start_at, end_at)` and the pure interval algebra
  the rest of the kernel is built on.

  Half-open semantics mean back-to-back intervals (`a.end_at == b.start_at`)
  do not overlap, so adjacent bookings are always legal. All operations are
  pure and deterministic; see `docs/specs/SP.03-algorithms.md` for the algebra
  laws these functions must satisfy.
  """

  @enforce_keys [:start_at, :end_at]
  defstruct [:start_at, :end_at, :kind, :meta]

  @typedoc "Classification of an interval; `nil` when irrelevant."
  @type kind :: :busy | :available | :blackout | :hold | nil

  @typedoc "A half-open interval `[start_at, end_at)` between UTC datetimes."
  @type t :: %__MODULE__{
          start_at: DateTime.t(),
          end_at: DateTime.t(),
          kind: kind(),
          meta: map() | nil
        }

  @doc """
  Builds an interval, validating that `start_at` precedes `end_at`.

  ## Examples

      iex> {:ok, interval} =
      ...>   ExBooking.Interval.new(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])
      ...>
      ...> interval.start_at
      ~U[2026-07-13 09:00:00Z]

      iex> ExBooking.Interval.new(~U[2026-07-13 10:00:00Z], ~U[2026-07-13 10:00:00Z])
      {:error, {:invalid, :interval, :empty_or_reversed}}

  """
  @spec new(DateTime.t(), DateTime.t(), keyword()) ::
          {:ok, t()} | {:error, {:invalid, :interval, :empty_or_reversed}}
  def new(start_at, end_at, opts \\ []) do
    if DateTime.compare(start_at, end_at) == :lt do
      {:ok, %__MODULE__{start_at: start_at, end_at: end_at, kind: opts[:kind], meta: opts[:meta]}}
    else
      {:error, {:invalid, :interval, :empty_or_reversed}}
    end
  end

  @doc """
  Like `new/3`, but raises `ArgumentError` on invalid bounds.

  ## Examples

      iex> ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z]).kind
      nil

  """
  @spec new!(DateTime.t(), DateTime.t(), keyword()) :: t()
  def new!(start_at, end_at, opts \\ []) do
    case new(start_at, end_at, opts) do
      {:ok, interval} -> interval
      {:error, reason} -> raise ArgumentError, "invalid interval: #{inspect(reason)}"
    end
  end

  @doc """
  Whether two intervals share any instant. Touching intervals do not overlap.

  ## Examples

      iex> a = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])
      ...> b = ExBooking.Interval.new!(~U[2026-07-13 10:00:00Z], ~U[2026-07-13 11:00:00Z])
      ...> ExBooking.Interval.overlaps?(a, b)
      false

      iex> a = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])
      ...> b = ExBooking.Interval.new!(~U[2026-07-13 09:30:00Z], ~U[2026-07-13 10:30:00Z])
      ...> ExBooking.Interval.overlaps?(a, b)
      true

  """
  @spec overlaps?(t(), t()) :: boolean()
  def overlaps?(%__MODULE__{} = a, %__MODULE__{} = b) do
    DateTime.compare(a.start_at, b.end_at) == :lt and
      DateTime.compare(b.start_at, a.end_at) == :lt
  end

  @doc """
  Whether `outer` fully contains `inner`.

  ## Examples

      iex> outer = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 12:00:00Z])
      ...> inner = ExBooking.Interval.new!(~U[2026-07-13 10:00:00Z], ~U[2026-07-13 11:00:00Z])
      ...> ExBooking.Interval.contains?(outer, inner)
      true

  """
  @spec contains?(t(), t()) :: boolean()
  def contains?(%__MODULE__{} = outer, %__MODULE__{} = inner) do
    DateTime.compare(outer.start_at, inner.start_at) != :gt and
      DateTime.compare(inner.end_at, outer.end_at) != :gt
  end

  @doc """
  Subtracts `b` from `a`, returning zero, one, or two remainder intervals.

  Remainders keep `a`'s `kind` and `meta`.

  ## Examples

      iex> a = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 12:00:00Z])
      ...> b = ExBooking.Interval.new!(~U[2026-07-13 10:00:00Z], ~U[2026-07-13 11:00:00Z])
      ...> [left, right] = ExBooking.Interval.subtract(a, b)
      ...> {left.end_at, right.start_at}
      {~U[2026-07-13 10:00:00Z], ~U[2026-07-13 11:00:00Z]}

  """
  @spec subtract(t(), t()) :: [t()]
  def subtract(%__MODULE__{} = a, %__MODULE__{} = b) do
    cond do
      not overlaps?(a, b) ->
        [a]

      contains?(b, a) ->
        []

      true ->
        left =
          if DateTime.compare(a.start_at, b.start_at) == :lt do
            %{a | end_at: b.start_at}
          end

        right =
          if DateTime.compare(b.end_at, a.end_at) == :lt do
            %{a | start_at: b.end_at}
          end

        Enum.reject([left, right], &is_nil/1)
    end
  end

  @doc """
  Subtracts every interval in `subtrahends` from every interval in `minuends`.

  Returns a sorted, non-overlapping list.

  ## Examples

      iex> free = [ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 12:00:00Z])]
      ...> busy = [ExBooking.Interval.new!(~U[2026-07-13 09:30:00Z], ~U[2026-07-13 10:00:00Z])]
      ...> [a, b] = ExBooking.Interval.subtract_all(free, busy)
      ...> {a.end_at, b.start_at}
      {~U[2026-07-13 09:30:00Z], ~U[2026-07-13 10:00:00Z]}

  """
  @spec subtract_all([t()], [t()]) :: [t()]
  def subtract_all(minuends, subtrahends) do
    normalized = merge(subtrahends)

    minuends
    |> Enum.flat_map(fn minuend ->
      Enum.reduce(normalized, [minuend], fn subtrahend, remainders ->
        Enum.flat_map(remainders, &subtract(&1, subtrahend))
      end)
    end)
    |> Enum.sort_by(& &1.start_at, DateTime)
  end

  @doc """
  Coalesces overlapping and touching intervals into normal form: sorted,
  disjoint, non-adjacent. Merged intervals keep the earliest interval's
  `kind` and `meta`.

  ## Examples

      iex> a = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])
      ...> b = ExBooking.Interval.new!(~U[2026-07-13 10:00:00Z], ~U[2026-07-13 11:00:00Z])
      ...> [merged] = ExBooking.Interval.merge([b, a])
      ...> {merged.start_at, merged.end_at}
      {~U[2026-07-13 09:00:00Z], ~U[2026-07-13 11:00:00Z]}

  """
  @spec merge([t()]) :: [t()]
  def merge(intervals) do
    intervals
    |> Enum.sort_by(& &1.start_at, DateTime)
    |> Enum.reduce([], &coalesce/2)
    |> Enum.reverse()
  end

  @doc """
  Intersects `interval` with `bounds`, returning `nil` when disjoint.

  ## Examples

      iex> a = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 12:00:00Z])
      ...> bounds = ExBooking.Interval.new!(~U[2026-07-13 10:00:00Z], ~U[2026-07-13 14:00:00Z])
      ...> clipped = ExBooking.Interval.clip(a, bounds)
      ...> {clipped.start_at, clipped.end_at}
      {~U[2026-07-13 10:00:00Z], ~U[2026-07-13 12:00:00Z]}

  """
  @spec clip(t(), t()) :: t() | nil
  def clip(%__MODULE__{} = interval, %__MODULE__{} = bounds) do
    start_at = max_dt(interval.start_at, bounds.start_at)
    end_at = min_dt(interval.end_at, bounds.end_at)

    if DateTime.compare(start_at, end_at) == :lt do
      %{interval | start_at: start_at, end_at: end_at}
    end
  end

  @doc """
  Widens an interval by minutes on each side. Used to apply buffers to busy
  time (see spec 03 §3 and §9).

  ## Examples

      iex> a = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 10:00:00Z])
      ...> inflated = ExBooking.Interval.inflate(a, 10, 5)
      ...> {inflated.start_at, inflated.end_at}
      {~U[2026-07-13 08:50:00Z], ~U[2026-07-13 10:05:00Z]}

  """
  @spec inflate(t(), non_neg_integer(), non_neg_integer()) :: t()
  def inflate(%__MODULE__{} = interval, before_min, after_min) do
    %{
      interval
      | start_at: DateTime.add(interval.start_at, -before_min, :minute),
        end_at: DateTime.add(interval.end_at, after_min, :minute)
    }
  end

  @doc """
  Whole minutes between the interval's endpoints.

  ## Examples

      iex> a = ExBooking.Interval.new!(~U[2026-07-13 09:00:00Z], ~U[2026-07-13 09:45:00Z])
      ...> ExBooking.Interval.duration_min(a)
      45

  """
  @spec duration_min(t()) :: non_neg_integer()
  def duration_min(%__MODULE__{} = interval) do
    interval.end_at
    |> DateTime.diff(interval.start_at, :second)
    |> div(60)
  end

  defp coalesce(interval, []), do: [interval]

  defp coalesce(interval, [previous | rest] = acc) do
    if DateTime.compare(interval.start_at, previous.end_at) == :gt do
      [interval | acc]
    else
      [%{previous | end_at: max_dt(previous.end_at, interval.end_at)} | rest]
    end
  end

  defp max_dt(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)
  defp min_dt(a, b), do: if(DateTime.compare(a, b) == :lt, do: a, else: b)
end
