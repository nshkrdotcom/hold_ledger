defmodule HoldLedgerReview.MixProject do
  use Mix.Project

  @source_url "https://github.com/nshkrdotcom/hold_ledger"

  def project do
    [
      app: :hold_ledger_review_web,
      version: "0.1.0",
      elixir: "~> 1.20.4",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      name: "Hold Ledger Explorer",
      description: "Explore Hold Ledger transitions, source claims and proof evidence.",
      source_url: @source_url,
      package: package(),
      docs: docs(),
      dialyzer: [plt_add_apps: [:ex_unit]],
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib config priv assets mix.exs .formatter.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/review_web.svg",
      favicon: "assets/lambda.svg",
      assets: %{"assets" => "assets"},
      extras: ["README.md", "CHANGELOG.md", {"LICENSE", [title: "MIT License"]}],
      groups_for_extras: [
        "Getting Started": ["README.md"],
        Reference: ["CHANGELOG.md", "LICENSE"]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {HoldLedgerReview.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.8", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false},
      {:hold_ledger, path: "../.."},
      # Keep transitive dependencies current beyond upstream minor-version constraints.
      {:boundary, "~> 0.12.0", override: true, runtime: false},
      {:erlexec, "~> 2.6.0", override: true},
      {:gproc, "~> 1.3.0", override: true},
      {:inference, "~> 0.5.2"},
      {:agent_session_manager, "~> 0.17.4"},
      {:codex_sdk, "~> 0.21.4"},
      {:phoenix, "~> 1.8.16"},
      {:phoenix_html, "~> 4.3.0"},
      {:phoenix_live_reload, "~> 1.7.0", only: :dev},
      {:phoenix_live_view, "~> 1.2.13"},
      {:lazy_html, "~> 0.1.13", only: :test},
      {:esbuild, "~> 0.10.1", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.2.0"},
      {:telemetry_poller, "~> 1.3.0"},
      {:jason, "~> 1.4.5"},
      {:dns_cluster, "~> 0.3.1"},
      {:bandit, "~> 1.14.1"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": [
        "compile",
        "tailwind hold_ledger_review_web",
        "esbuild hold_ledger_review_web"
      ],
      "assets.deploy": [
        "tailwind hold_ledger_review_web --minify",
        "esbuild hold_ledger_review_web --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "dialyzer",
        "test --warnings-as-errors"
      ]
    ]
  end
end
