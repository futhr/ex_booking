defmodule ExBooking.PackageVerificationTest do
  @moduledoc false

  use ExUnit.Case, async: false

  @source Path.expand("..", __DIR__)
  @script Path.join(@source, "scripts/verify_package.exs")
  @mix_paths ~w(MIX_BUILD_PATH MIX_BUILD_ROOT MIX_DEPS_PATH MIX_LOCKFILE)

  @tag timeout: 300_000
  test "the archive consumers and notebooks ignore inherited Mix paths" do
    temporary =
      Path.join(
        System.tmp_dir!(),
        "ex-booking-package-paths-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir!(temporary)
    on_exit(fn -> File.rm_rf!(temporary) end)

    environment =
      for name <- @mix_paths do
        path = Path.join(temporary, name)
        File.write!(path, "package verification sentinel\n")
        {name, path}
      end

    {output, status} =
      System.cmd("elixir", [@script],
        cd: @source,
        env: environment,
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "fresh production consumer and README quick start passed."
    assert output =~ "Packaged consumer and all notebook setup/example cells verified."

    for {_, path} <- environment do
      assert File.regular?(path)
      assert File.read!(path) == "package verification sentinel\n"
    end
  end
end
