defmodule HoldLedger.MixProject do
  use Mix.Project

  @version "0.0.0-dev"
  @source_url "https://github.com/nshkrdotcom/hold_ledger"

  def project do
    [
      app: :hold_ledger,
      version: @version,
      name: "Hold Ledger",
      description: "An authorization-hold ledger with a journaled runtime and formal laws.",
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      elixir: "~> 1.20.4",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_paths: ["test"],
      test_ignore_filters: [~r"test/support/"]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {HoldLedger.Application, []}
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false},
      {:lynx,
       git: "https://github.com/josevalim/lynx.git",
       ref: "3b44de83fb63503e12b84233de70cf0647e7e63e",
       only: :test},
      {:stream_data, "~> 1.4.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs .formatter.exs README.md LICENSE CHANGELOG.md guides assets/*.svg)
    ]
  end

  defp docs do
    [
      main: "readme",
      authors: ["nshkrdotcom"],
      source_ref: if(String.contains?(@version, "-dev"), do: "main", else: "v#{@version}"),
      logo: "assets/hold_ledger.svg",
      favicon: "assets/hold_ledger.svg",
      assets: %{"assets" => "assets"},
      formatters: ["html", "markdown", "epub"],
      extras:
        ["README.md"] ++
          Path.wildcard("guides/*.md") ++
          ["CHANGELOG.md", {"LICENSE", [title: "MIT License"]}],
      groups_for_extras: [
        "Getting Started": ["README.md", "guides/getting-started.md"],
        "Reviewing Correctness": ["guides/human_review.md"],
        "Using the Ledger": [
          "guides/specification.md",
          "guides/architecture.md",
          "guides/runtime.md",
          "guides/processors.md"
        ],
        "Testing and Verification": [
          "guides/testing.md",
          "guides/formal_verification_crash_course.md",
          "guides/verification.md"
        ],
        Reference: ["guides/troubleshooting.md", "CHANGELOG.md", "LICENSE"]
      ],
      groups_for_modules: [
        Overview: [HoldLedger],
        "Ledger and Specification": [HoldLedger.Ledger, HoldLedger.Spec],
        Runtime: [
          HoldLedger.Application,
          HoldLedger.Server,
          HoldLedger.Journal,
          HoldLedger.Processor,
          HoldLedger.Processor.Sim,
          HoldLedger.EffectExecutor,
          HoldLedger.Attempts,
          HoldLedger.Outbox,
          HoldLedger.Event
        ]
      ]
    ]
  end
end
