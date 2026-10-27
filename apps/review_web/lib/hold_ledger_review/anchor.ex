defmodule HoldLedgerReview.Anchor do
  @moduledoc "Curated source definitions with unique selectors and content-bound IDs."
  def descriptors(c) do
    base = [
      {"policy", "guides/specification.md", "# Specification", :file},
      {"code", "lib/hold_ledger/ledger.ex",
       "  def " <> c.operation <> if(c.operation == "request", do: "({", else: "(\n"),
       :definition},
      {"spec.valid", "lib/hold_ledger/spec.ex", "  def valid?({", :definition},
      {"spec.effects", "lib/hold_ledger/spec.ex", "  def effects_valid?(", :definition},
      {"spec.retention", "lib/hold_ledger/spec.ex", "  def exposed_entry?({", :definition},
      {"spec.eligibility", "lib/hold_ledger/spec.ex", "  def request_eligible?(state",
       :definition},
      {"policy.traces", "test/human_policy_traces_test.exs", "defmodule ", :file}
    ]

    base ++
      Enum.flat_map(c.laws, fn {slug, file, arity} ->
        [
          {"law." <> slug, "test/laws/" <> slug <> "_test.exs", "defmodule ", :file},
          {"lean." <> slug, "test/support/lean/" <> file <> ".lean",
           "theorem «" <> slug <> "/" <> to_string(arity) <> "»", :theorem}
        ]
      end)
  end

  def build(root, c) do
    Enum.reduce_while(descriptors(c), {:ok, %{}}, fn {id, path, selector, kind}, {:ok, acc} ->
      case resolve(root, path, selector, kind, Enum.map(descriptors(c), &elem(&1, 1))) do
        {:ok, a} ->
          {:cont, {:ok, Map.put(acc, c.id <> "." <> id, Map.put(a, :id, c.id <> "." <> id))}}

        error ->
          {:halt, error}
      end
    end)
  end

  def resolve(root, path, selector, kind, allowlist) do
    with true <- path in allowlist,
         {:ok, bytes} <- read_under(root, path),
         [{offset, _}] <- :binary.matches(bytes, selector) do
      start = if kind == :file, do: 0, else: offset
      tail = binary_part(bytes, start, byte_size(bytes) - start)

      text =
        case kind do
          :definition -> Regex.split(~r/\n  (?:@doc|def |defp )/, tail, parts: 2) |> hd()
          :theorem -> Regex.split(~r/\n(?:theorem |end )/, tail, parts: 2) |> hd()
          :file -> tail
        end

      {:ok,
       %{
         path: path,
         line: length(String.split(binary_part(bytes, 0, start), "\n")),
         text: text,
         sha256: sha(bytes),
         anchor_sha256: sha(path <> text <> sha(bytes))
       }}
    else
      _ -> {:error, {:invalid_anchor, path, selector}}
    end
  end

  def read_under(root, path) when is_binary(path) do
    full = Path.expand(path, root)
    parts = Path.split(Path.relative_to(full, root))

    safe =
      Path.type(path) != :absolute and
        not String.starts_with?(Path.relative_to(full, root), "..") and
        Enum.reduce_while(parts, root, fn part, acc ->
          next = Path.join(acc, part)

          case File.lstat(next) do
            {:ok, %{type: :symlink}} -> {:halt, false}
            {:ok, _} -> {:cont, next}
            _ -> {:halt, false}
          end
        end) != false

    if safe, do: File.read(full), else: {:error, :unsafe_path}
  end

  def read_under(_, _), do: {:error, :unsafe_path}
  def sha(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
