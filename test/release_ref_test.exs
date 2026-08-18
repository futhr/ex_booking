Code.require_file("../scripts/release_ref.exs", __DIR__)

defmodule ExBooking.ReleaseRefTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias ExBooking.ReleaseRef

  setup do
    repository =
      Path.join(
        System.tmp_dir!(),
        "ex_booking_release_ref_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(repository)
    git!(repository, ["init", "--quiet"])
    git!(repository, ["config", "user.email", "release-test@example.invalid"])
    git!(repository, ["config", "user.name", "Release Test"])
    File.write!(Path.join(repository, "release.txt"), "first\n")
    git!(repository, ["add", "release.txt"])
    git!(repository, ["commit", "--quiet", "-m", "first"])
    sha = git!(repository, ["rev-parse", "HEAD"])
    git!(repository, ["tag", "v0.1.0"])

    on_exit(fn -> File.rm_rf!(repository) end)

    %{environment: release_environment(sha), repository: repository, sha: sha}
  end

  test "accepts the exact project tag at the triggering commit", context do
    assert :ok =
             ReleaseRef.verify!("0.1.0", context.environment, context.repository)
  end

  test "rejects a branch ref", context do
    environment = Map.put(context.environment, "GITHUB_REF", "refs/heads/main")

    assert_raise ArgumentError, ~r/release must run from refs\/tags\/v0\.1\.0/, fn ->
      ReleaseRef.verify!("0.1.0", environment, context.repository)
    end
  end

  test "rejects a version-mismatched tag", context do
    environment = Map.put(context.environment, "GITHUB_REF", "refs/tags/v9.9.9")

    assert_raise ArgumentError, ~r/release must run from refs\/tags\/v0\.1\.0/, fn ->
      ReleaseRef.verify!("0.1.0", environment, context.repository)
    end
  end

  test "rejects a tag that does not resolve to the triggering SHA", context do
    File.write!(Path.join(context.repository, "release.txt"), "second\n")
    git!(context.repository, ["add", "release.txt"])
    git!(context.repository, ["commit", "--quiet", "-m", "second"])
    second_sha = git!(context.repository, ["rev-parse", "HEAD"])
    environment = release_environment(second_sha)

    assert_raise ArgumentError, ~r/does not resolve|resolves to .* not triggering SHA/, fn ->
      ReleaseRef.verify!("0.1.0", environment, context.repository)
    end
  end

  test "rejects a checkout that differs from the triggering SHA", context do
    File.write!(Path.join(context.repository, "release.txt"), "second\n")
    git!(context.repository, ["add", "release.txt"])
    git!(context.repository, ["commit", "--quiet", "-m", "second"])

    assert_raise ArgumentError, ~r/checked out HEAD .* does not match triggering SHA/, fn ->
      ReleaseRef.verify!("0.1.0", context.environment, context.repository)
    end
  end

  test "rejects a malformed triggering SHA", context do
    environment = Map.put(context.environment, "GITHUB_SHA", "not-a-sha")

    assert_raise ArgumentError, ~r/GITHUB_SHA must be a lowercase 40-character commit SHA/, fn ->
      ReleaseRef.verify!("0.1.0", environment, context.repository)
    end
  end

  defp release_environment(sha) do
    %{"GITHUB_REF" => "refs/tags/v0.1.0", "GITHUB_SHA" => sha}
  end

  defp git!(repository, arguments) do
    options = [
      stderr_to_stdout: true,
      env: [{"CODECOV_TOKEN", nil}, {"GITHUB_TOKEN", nil}, {"HEX_API_KEY", nil}]
    ]

    case System.cmd("git", ["-C", repository | arguments], options) do
      {output, 0} -> String.trim(output)
      {output, status} -> flunk("git failed with status #{status}: #{output}")
    end
  end
end
