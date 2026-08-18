defmodule ExBooking.ReleaseRef do
  @moduledoc false

  @sha_pattern ~r/\A[0-9a-f]{40}\z/

  @spec verify!(String.t(), %{String.t() => String.t()}, Path.t()) :: :ok
  def verify!(version, environment, repository \\ ".") do
    expected_ref = "refs/tags/v#{version}"
    github_ref = fetch_environment!(environment, "GITHUB_REF")
    github_sha = fetch_environment!(environment, "GITHUB_SHA")

    unless github_ref == expected_ref do
      raise ArgumentError,
            "release must run from #{expected_ref}; received #{inspect(github_ref)}"
    end

    unless Regex.match?(@sha_pattern, github_sha) do
      raise ArgumentError,
            "GITHUB_SHA must be a lowercase 40-character commit SHA; " <>
              "received #{inspect(github_sha)}"
    end

    tag_sha = resolve_commit!(repository, expected_ref)

    unless tag_sha == github_sha do
      raise ArgumentError,
            "#{expected_ref} resolves to #{tag_sha}, not triggering SHA #{github_sha}"
    end

    head_sha = resolve_commit!(repository, "HEAD")

    unless head_sha == github_sha do
      raise ArgumentError,
            "checked out HEAD #{head_sha} does not match triggering SHA #{github_sha}"
    end

    :ok
  end

  defp fetch_environment!(environment, key) do
    case Map.fetch(environment, key) do
      {:ok, value} when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "#{key} is required"
    end
  end

  defp resolve_commit!(repository, ref) do
    case System.cmd(
           "git",
           ["-C", repository, "rev-parse", "--verify", "#{ref}^{commit}"],
           stderr_to_stdout: true
         ) do
      {sha, 0} ->
        String.trim(sha)

      {output, _status} ->
        raise ArgumentError,
              "cannot resolve #{ref} in #{repository}: #{String.trim(output)}"
    end
  end
end
