Code.require_file("../scripts/notebook_outputs.exs", __DIR__)

defmodule ExBooking.NotebooksTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias ExBooking.NotebookOutputs

  @notebooks NotebookOutputs.notebook_paths()

  test "the notebooks directory is not empty" do
    refute Enum.empty?(NotebookOutputs.notebook_paths())
  end

  for path <- @notebooks do
    describe Path.basename(path) do
      @path path

      test "every code cell evaluates and saved outputs are current" do
        text = File.read!(@path)

        case NotebookOutputs.mismatches(text, @path) do
          [] ->
            :ok

          [{cell, expected, saved} | _] ->
            flunk("""
            #{Path.basename(@path)} cell #{cell} has a stale saved output.
            Regenerate with: mix run scripts/regen_notebook_outputs.exs

            evaluated: #{expected}
            saved:     #{saved}
            """)
        end
      end

      test "the setup cell pins the released ex_booking version" do
        pin = NotebookOutputs.expected_pin(Mix.Project.config()[:version])
        setup = NotebookOutputs.setup_source(File.read!(@path))

        assert setup =~ pin,
               "setup cell must contain #{pin} (matching mix.exs); " <>
                 "update the Mix.install cell in #{Path.basename(@path)}"
      end

      test "the setup cell configures the tz database" do
        setup = NotebookOutputs.setup_source(File.read!(@path))
        assert setup =~ "Calendar.put_time_zone_database(Tz.TimeZoneDatabase)"
      end
    end
  end

  test "tokenize/render round-trips every notebook byte-for-byte" do
    for path <- @notebooks do
      text = File.read!(path)

      round_tripped =
        text
        |> NotebookOutputs.tokenize()
        |> NotebookOutputs.render()

      assert round_tripped == text
    end
  end
end
