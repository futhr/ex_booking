[
  parallel: true,
  skipped: true,
  tools: [
    # Dependencies
    {:deps_get, command: "mix deps.get"},

    # Elixir compilation (--force is default for ex_check compiler)
    {:compiler, command: "mix compile --warnings-as-errors"},

    # Formatting
    {:formatter, command: "mix format --check-formatted"},

    # Static analysis
    {:credo, command: "mix credo --strict"},

    # Security and dependencies
    {:mix_audit, command: "mix deps.audit"},
    {:hex_audit, command: "mix hex.audit"},

    # Type checking
    {:dialyzer, command: "mix dialyzer"},

    # Documentation
    {:doctor, command: "mix doctor"},
    {:ex_doc, command: "mix docs"},

    # Extracted Hex archive, fresh production consumer, and notebook setup cells
    {:package_consumer, command: "mix verify.package"},

    # Tests
    {:ex_unit, command: "mix test --cover"}
  ]
]
