defmodule ExBooking.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/refpath/ex_booking"

  def project do
    [
      app: :ex_booking,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      aliases: aliases(),
      name: "ExBooking"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.lcov": :test,
        cover: :test,
        "cover.html": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Core
      {:tz, "~> 0.28"},
      {:nimble_options, "~> 1.1"},

      # Code quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},

      # Documentation
      {:ex_doc, "~> 0.35", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev, :test], runtime: false},
      {:doctest_formatter, "~> 0.4", only: [:dev, :test], runtime: false},

      # Testing
      {:excoveralls, "~> 0.18", only: :test},
      {:stream_data, "~> 1.3", only: :test},

      # Benchmarks
      {:benchee, "~> 1.3", only: :dev, runtime: false},
      {:benchee_markdown, "~> 0.3", only: :dev, runtime: false},

      # Release
      {:git_ops, "~> 2.6", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Pure booking kernel for sales scheduling: timezone-safe availability, " <>
      "slot generation, conflict detection, assignment strategies, and " <>
      "deterministic booking decisions. No database, no processes, no side effects."
  end

  defp package do
    [
      name: "ex_booking",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://hexdocs.pm/ex_booking"
      },
      files: ~w[
        lib
        docs
        .formatter.exs
        mix.exs
        README.md
        LICENSE
        CONTRIBUTING.md
        AGENTS.md
        CLAUDE.md
        CHANGELOG.md
      ],
      maintainers: ["Refpath Maintainers"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md": [title: "Overview"],
        "docs/research/R.01-booking-space-and-kernel-rationale.md": [title: "Research"],
        "docs/specs/SP.00-overview.md": [title: "Spec: Overview"],
        "docs/specs/SP.01-data-model.md": [title: "Spec: Data Model"],
        "docs/specs/SP.02-public-api.md": [title: "Spec: Public API"],
        "docs/specs/SP.03-algorithms.md": [title: "Spec: Algorithms"],
        "docs/specs/SP.04-assignment.md": [title: "Spec: Assignment"],
        "docs/specs/SP.05-lifecycle-and-events.md": [title: "Spec: Lifecycle & Events"],
        "docs/specs/SP.06-testing-strategy.md": [title: "Spec: Testing Strategy"],
        "docs/specs/SP.07-roadmap.md": [title: "Spec: Roadmap"],
        "CHANGELOG.md": [title: "Changelog"],
        "CONTRIBUTING.md": [title: "Contributing"],
        "CLAUDE.md": [title: "Agent Guide"],
        LICENSE: [title: "License"]
      ],
      groups_for_extras: [
        "Getting Started": ~r/README/,
        Research: ~r/research/,
        Specification: ~r/specs/,
        Reference: ~r/CHANGELOG|CONTRIBUTING|CLAUDE|LICENSE/
      ],
      groups_for_modules: [
        "Core API": [
          ExBooking,
          ExBooking.Decision,
          ExBooking.Request
        ],
        "Temporal Math": [
          ExBooking.Interval,
          ExBooking.Schedule,
          ExBooking.Slotting,
          ExBooking.Availability
        ],
        "Domain Model": [
          ExBooking.AvailabilityRule,
          ExBooking.MeetingType,
          ExBooking.Resource
        ],
        "Assignment & Policy": [
          ExBooking.Assignment,
          ExBooking.Policy
        ],
        "Lifecycle & Events": [
          ExBooking.Hold,
          ExBooking.Event
        ]
      ],
      skip_undefined_reference_warnings_on: [
        "CHANGELOG.md"
      ],
      source_ref: "v#{@version}",
      source_url: @source_url,
      formatters: ["html"]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyxir.plt"},
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling, :missing_return, :underspecs, :extra_return]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "deps.compile"],
      lint: ["format --check-formatted", "credo --strict", "dialyzer"],
      "test.cover": ["coveralls"],
      bench: ["run bench/run.exs"],
      ci: ["setup", "lint", "test.cover"],

      # Release
      release: ["git_ops.release"]
    ]
  end
end
