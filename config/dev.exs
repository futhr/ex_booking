import Config

notebook_requirement = fn version ->
  parsed = Version.parse!(version)
  "~> #{parsed.major}.#{parsed.minor}"
end

# Git Ops - automated changelog and version management
config :git_ops,
  mix_project: Mix.Project.get!(),
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/futhr/ex_booking",
  version_tag_prefix: "v",
  manage_mix_version?: true,
  manage_readme_version: "README.md",
  managed_files:
    Enum.map(
      [
        "notebooks/assignment-and-policy.livemd",
        "notebooks/availability-and-slotting.livemd",
        "notebooks/interval-algebra.livemd",
        "notebooks/lifecycle-and-interop.livemd",
        "notebooks/schedules-and-dst.livemd",
        "notebooks/tour.livemd"
      ],
      &{&1, notebook_requirement, notebook_requirement}
    )
