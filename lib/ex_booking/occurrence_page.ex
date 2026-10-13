defmodule ExBooking.OccurrencePage do
  @moduledoc """
  A bounded ordered page of original occurrences.

  A non-nil cursor means another candidate position remains to be considered;
  the last continuation may therefore be empty. The consumer owns processed
  result tracking and any execution.

  ## Example

      iex> page = %ExBooking.OccurrencePage{}
      ...> {page.occurrences, page.next_cursor}
      {[], nil}
  """

  defstruct occurrences: [], next_cursor: nil

  @typedoc "Enumeration output and optional query-bound continuation."
  @type t :: %__MODULE__{
          occurrences: [ExBooking.Occurrence.t()],
          next_cursor: ExBooking.OccurrenceCursor.t() | nil
        }
end
