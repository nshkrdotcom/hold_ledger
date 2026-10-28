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

  @doc "Read a source set with directory checks shared only within this call."
  def read_many_under(root, paths) do
    Enum.reduce_while(Enum.uniq(paths), {:ok, %{}, %{}}, fn path, {:ok, files, checked} ->
      case read_checked(root, path, checked) do
        {:ok, bytes, next_checked} -> {:cont, {:ok, Map.put(files, path, bytes), next_checked}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, files, _checked} -> {:ok, files}
      error -> error
    end
  end

  defp read_checked(root, path, checked) when is_binary(path) do
    full = Path.expand(path, root)
    relative = Path.relative_to(full, root)

    if Path.type(path) == :absolute or String.starts_with?(relative, "..") do
      {:error, :unsafe_path}
    else
      with {:ok, next_checked} <- check_parts(root, Path.split(relative), checked),
           {:ok, bytes} <- File.read(full) do
        {:ok, bytes, next_checked}
      end
    end
  end

  defp read_checked(_root, _path, _checked), do: {:error, :unsafe_path}

  defp check_parts(_parent, [], checked), do: {:ok, checked}

  defp check_parts(parent, [part | rest], checked) do
    path = Path.join(parent, part)

    case Map.fetch(checked, path) do
      {:ok, :safe} -> check_parts(path, rest, checked)
      :error -> check_part(path, rest, checked)
    end
  end

  defp check_part(path, rest, checked) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} -> {:error, :unsafe_path}
      {:ok, _} -> check_parts(path, rest, Map.put(checked, path, :safe))
      _ -> {:error, :unsafe_path}
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
