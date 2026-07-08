import Config

# Git Ops - automated changelog and version management
config :git_ops,
  mix_project: Mix.Project.get!(),
  changelog_file: "CHANGELOG.md",
  repository_url: "https://github.com/futhr/ex_booking",
  version_tag_prefix: "v",
  manage_mix_version?: true,
  manage_readme_version: "README.md"
