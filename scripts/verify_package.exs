Code.require_file("notebook_outputs.exs", __DIR__)

defmodule ExBooking.PackageVerification do
  @moduledoc false

  alias ExBooking.NotebookOutputs

  def run do
    source = Path.expand("..", __DIR__)

    temporary =
      Path.join(
        System.tmp_dir!(),
        "ex_booking_package_#{System.pid()}_#{System.unique_integer([:positive])}"
      )

    package = Path.join(temporary, "package")
    consumer = Path.join(temporary, "consumer")
    archive = Path.join(temporary, "package.tar")
    File.mkdir!(temporary)
    File.mkdir_p!(package)
    File.mkdir_p!(consumer)

    try do
      command!("mix", ["hex.build", "--output", archive], source)
      command!("tar", ["-xf", archive, "-C", package], temporary)
      command!("tar", ["-xzf", "contents.tar.gz"], package)
      verify_consumer!(consumer, package)
      verify_notebooks!(package, temporary)
      IO.puts("Packaged consumer and all notebook setup/example cells verified.")
    after
      File.rm_rf!(temporary)
    end
  end

  defp verify_consumer!(consumer, package) do
    File.write!(Path.join(consumer, "mix.exs"), """
    defmodule PackageConsumer.MixProject do
      use Mix.Project
      def project do
        [app: :package_consumer, version: "0.0.0",
         deps: [{:ex_booking, path: #{inspect(package)}}]]
      end
    end
    """)

    File.write!(Path.join(consumer, "verify.exs"), """
    Calendar.put_time_zone_database(Tz.TimeZoneDatabase)
    expected = [:elixir, :kernel, :logger, :nimble_options, :stdlib, :tz]
    ^expected = :ex_booking |> Application.spec(:applications) |> Enum.sort()
    [] = Application.spec(:ex_booking, :mod)
    meeting = %ExBooking.MeetingType{id: "intro", duration_min: 30}
    resource = %ExBooking.Resource{id: "host", timezone: "Europe/Stockholm"}
    rule = %ExBooking.AvailabilityRule{
      timezone: "Europe/Stockholm",
      windows: [%{weekday: 1, start_time: ~T[09:00:00], end_time: ~T[10:00:00]}]
    }
    now = ~U[2026-07-12 00:00:00Z]
    {:ok, [first, _]} = ExBooking.available_slots(meeting, [resource], [rule],
      now: now, from: ~U[2026-07-13 00:00:00Z], until: ~U[2026-07-14 00:00:00Z])
    ~U[2026-07-13 07:00:00Z] = first.start_at
    request = %ExBooking.Request{meeting_type_id: "intro", slot: first,
      invitee_timezone: "America/New_York"}
    {:ok, %ExBooking.Decision{status: :ok, resource_ids: ["host"]}} =
      ExBooking.decide(request, meeting, [resource], [rule], now: now)
    IO.puts("Fresh production consumer passed.")
    """)

    command!("mix", ["deps.get"], consumer, [{"MIX_ENV", "prod"}])
    command!("mix", ["run", "verify.exs"], consumer, [{"MIX_ENV", "prod"}])
  end

  defp verify_notebooks!(package, temporary) do
    notebooks = Path.wildcard(Path.join(package, "notebooks/*.livemd"))
    if notebooks == [], do: raise("Hex package is missing its notebook sources")
    engine = Path.join(__DIR__, "notebook_outputs.exs")

    notebooks
    |> Enum.group_by(&NotebookOutputs.setup_source(File.read!(&1)))
    |> Enum.with_index()
    |> Enum.each(fn {{setup, paths}, index} ->
      # The file lives beside the packaged notebooks so their actual __DIR__
      # setup expression installs the extracted archive, not the source tree.
      script = Path.join(package, "notebooks/verify_setup_#{index}.exs")

      File.write!(script, """
      #{setup}
      Code.require_file(#{inspect(engine)})
      for path <- #{inspect(paths)} do
        [] = ExBooking.NotebookOutputs.mismatches(File.read!(path), path)
        IO.puts("Verified notebook: " <> Path.basename(path))
      end
      """)

      command!("elixir", [script], temporary, [
        {"MIX_ENV", "prod"},
        {"MIX_INSTALL_DIR", Path.join(temporary, "install_#{index}")}
      ])
    end)
  end

  defp command!(executable, args, directory, environment \\ []) do
    clean_environment = [
      {"MIX_BUILD_PATH", nil},
      {"MIX_DEPS_PATH", nil},
      {"MIX_LOCKFILE", nil}
    ]

    {output, status} =
      System.cmd(executable, args,
        cd: directory,
        env: clean_environment ++ environment,
        stderr_to_stdout: true
      )

    IO.write(output)
    if status != 0, do: raise("#{executable} #{Enum.join(args, " ")} exited with #{status}")
  end
end

ExBooking.PackageVerification.run()
