defmodule HoldLedgerReview.Anchor do
  @moduledoc "Safe source excerpts and content-bound IDs; no fixed case catalogs."
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
