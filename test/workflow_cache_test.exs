defmodule ExBooking.WorkflowCacheTest do
  @moduledoc false

  use ExUnit.Case, async: true

  test "dependency cache keys never share builds between configured BEAM runtimes" do
    keys =
      for {lane, cache} <- caches("deps"),
          template <- [cache["key"] | String.split(cache["restore-keys"] || "", "\n", trim: true)] do
        {render(template, lane), {lane.otp, lane.elixir}}
      end

    assert keys != []

    for {key, runtimes} <- Enum.group_by(keys, &elem(&1, 0), &elem(&1, 1)) do
      assert length(Enum.uniq(runtimes)) == 1,
             "cache #{key} shares incompatible runtimes: #{inspect(Enum.uniq(runtimes))}"
    end
  end

  test "every PLT cache invalidates after either OTP or Elixir patch changes" do
    versions = %{otp: "29.0.4", elixir: "1.20.4", erts: "17.0.4"}
    caches = caches("priv/plts")
    assert caches != []

    for {lane, cache} <- caches do
      original = render(cache["key"], lane, versions)
      otp_patch = render(cache["key"], lane, %{versions | otp: "29.0.5", erts: "17.0.5"})
      elixir_patch = render(cache["key"], lane, %{versions | elixir: "1.20.5"})

      refute original == otp_patch, "#{lane.name} reuses its PLT after an OTP patch change"
      refute original == elixir_patch, "#{lane.name} reuses its PLT after an Elixir patch change"
    end
  end

  defp caches(path) do
    for lane <- lanes(),
        step <- lane.job["steps"],
        String.starts_with?(step["uses"] || "", "actions/cache@"),
        path in String.split(step["with"]["path"] || "", "\n", trim: true),
        do: {lane, step["with"]}
  end

  defp lanes do
    for file <- ["ci.yml", "publish.yml"],
        {name, job} <- YamlElixir.read_from_file!(".github/workflows/" <> file)["jobs"],
        row <- get_in(job, ["strategy", "matrix", "include"]) || [%{}] do
      setup = Enum.find(job["steps"], &String.starts_with?(&1["uses"] || "", "erlef/setup-beam@"))

      %{
        name: "#{file}:#{name}",
        job: job,
        otp: version(setup["with"]["otp-version"], row),
        elixir: version(setup["with"]["elixir-version"], row)
      }
    end
  end

  defp version("${{ matrix." <> rest, row), do: Map.fetch!(row, String.trim_trailing(rest, " }}"))
  defp version(value, _), do: value

  defp render(template, lane, versions \\ nil) do
    versions = versions || %{otp: lane.otp, elixir: lane.elixir, erts: "erts-#{lane.otp}"}

    context = %{
      "runner.os" => "Linux",
      "matrix.otp" => lane.otp,
      "matrix.elixir" => lane.elixir,
      "hashFiles('**/mix.lock')" => "lock-digest"
    }

    context = Enum.reduce(lane.job["steps"], context, &step_outputs(&1["id"], &2, versions))

    Regex.replace(~r/\$\{\{\s*(.*?)\s*\}\}/, template, fn _, key ->
      Map.fetch!(context, String.trim(key))
    end)
  end

  defp step_outputs(nil, context, _), do: context

  defp step_outputs(id, context, versions) do
    Map.merge(context, %{
      "steps.#{id}.outputs.otp-version" => versions.otp,
      "steps.#{id}.outputs.elixir-version" => versions.elixir,
      "steps.#{id}.outputs.erts" => versions.erts,
      "steps.#{id}.outputs.elixir" => versions.elixir
    })
  end
end
