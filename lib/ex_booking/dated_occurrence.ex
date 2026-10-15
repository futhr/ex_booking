defmodule ExBooking.DatedOccurrence do
  @moduledoc """
  An explicit calendar day with an optional independent UTC instant.

  `reference` is an opaque caller coordinate. The consumer owns its meaning,
  uniqueness and authority; the kernel preserves it without interpreting it.

  ## Example

      iex> occurrence = %ExBooking.DatedOccurrence{on: ~D[2026-10-14]}
      ...> {occurrence.on, occurrence.starts_at}
      {~D[2026-10-14], nil}
  """

  @enforce_keys [:on]
  defstruct [:on, :starts_at, :reference]

  @typedoc "Supplied date, optional UTC instant and opaque consumer reference."
  @type t :: %__MODULE__{
          on: Date.t(),
          starts_at: DateTime.t() | nil,
          reference: String.t() | nil
        }
end
