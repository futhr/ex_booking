# Benchmark harness for ExBooking.
#
# Usage: mix bench
#
# Exercises the two hot paths called out in docs/specs/SP.03-algorithms.md §10:
# interval subtraction over a large busy set, and availability assembly across
# a multi-week horizon. Assembly must stay sort-merge based (no quadratic
# scans) as the busy set and horizon grow.

alias ExBooking.AvailabilityRule
alias ExBooking.Interval
alias ExBooking.MeetingType
alias ExBooking.Resource

base = ~U[2026-07-13 00:00:00Z]

busy_set = fn count ->
  for i <- 0..(count - 1) do
    start_at = DateTime.add(base, i * 90, :minute)

    %Interval{
      start_at: start_at,
      end_at: DateTime.add(start_at, 30, :minute),
      kind: :busy
    }
  end
end

offerable = [Interval.new!(base, DateTime.add(base, 28, :day))]

rule = %AvailabilityRule{
  timezone: "Etc/UTC",
  windows:
    for weekday <- 1..5 do
      %{weekday: weekday, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}
    end
}

meeting_type = %MeetingType{id: "demo_30", duration_min: 30, slot_interval_min: 15}

horizon = [
  now: base,
  from: base,
  until: DateTime.add(base, 28, :day)
]

Benchee.run(
  %{
    "subtract_all/2 over 500 busy intervals" => fn ->
      Interval.subtract_all(offerable, busy_set.(500))
    end,
    "available_slots/4 over a 4-week horizon (200 busy)" => fn ->
      resource = %Resource{id: "res_1", timezone: "Etc/UTC", busy: busy_set.(200)}
      {:ok, _slots} = ExBooking.available_slots(meeting_type, [resource], [rule], horizon)
    end
  },
  time: 3,
  memory_time: 1,
  formatters: [Benchee.Formatters.Console]
)
