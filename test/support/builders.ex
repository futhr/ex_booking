defmodule ExBooking.TestBuilders do
  @moduledoc false

  alias ExBooking.AvailabilityRule
  alias ExBooking.Interval
  alias ExBooking.MeetingType
  alias ExBooking.Request
  alias ExBooking.Resource

  @type builder_name :: :interval | :meeting_type | :request | :resource | :rule

  @doc "Builds a kernel struct by name with optional overrides."
  @spec build(builder_name(), Enumerable.t()) :: struct()
  def build(name, overrides \\ [])

  def build(:interval, overrides) do
    defaults = %{
      start_at: ~U[2026-07-13 09:00:00Z],
      end_at: ~U[2026-07-13 10:00:00Z]
    }

    struct!(Interval, Map.merge(defaults, Map.new(overrides)))
  end

  def build(:rule, overrides) do
    defaults = %{
      timezone: "Europe/Stockholm",
      windows: [
        %{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[17:00:00]},
        %{weekday: 2, start_time: ~T[09:00:00], end_time: ~T[17:00:00]},
        %{weekday: 3, start_time: ~T[09:00:00], end_time: ~T[17:00:00]},
        %{weekday: 4, start_time: ~T[09:00:00], end_time: ~T[17:00:00]},
        %{weekday: 5, start_time: ~T[09:00:00], end_time: ~T[16:00:00]}
      ]
    }

    struct!(AvailabilityRule, Map.merge(defaults, Map.new(overrides)))
  end

  def build(:resource, overrides) do
    defaults = %{id: "res_1", timezone: "Europe/Stockholm"}
    struct!(Resource, Map.merge(defaults, Map.new(overrides)))
  end

  def build(:meeting_type, overrides) do
    defaults = %{id: "demo_30", duration_min: 30, slot_interval_min: 15}
    struct!(MeetingType, Map.merge(defaults, Map.new(overrides)))
  end

  def build(:request, overrides) do
    defaults = %{
      meeting_type_id: "demo_30",
      invitee_timezone: "America/New_York",
      slot: build(:interval)
    }

    struct!(Request, Map.merge(defaults, Map.new(overrides)))
  end
end
