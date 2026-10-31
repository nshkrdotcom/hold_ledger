defmodule HoldLedgerReviewWeb.Learning do
  @moduledoc "Presentation data over the existing trace and source-reading APIs."

  alias HoldLedger.Ledger
  alias HoldLedgerReview.{Anchor, Config, ProofReading, TermCodec, Trace}
  alias HoldLedgerReviewWeb.Education

  @moments [
    %{
      index: 0,
      label: "Start",
      title: "An empty account has room for a hold.",
      text:
        "The account has a 100¢ amount limit and two hold slots. Nothing has been requested yet.",
      claim: "po_i",
      claim_label: "Read the initial-state claim",
      native_event: nil,
      next_action: "Reserve 100¢",
      source_function: "Ledger.init/2"
    },
    %{
      index: 1,
      label: "Request",
      title: "A new request needs 100¢.",
      text:
        "Request 11 asks for exactly the available amount. The ledger accepts it, reserves 100¢ and uses one of the two slots.",
      claim: "po_a2",
      claim_label: "Read the exact-fit claim",
      native_event: {:request, 11, 100},
      next_action: "Request authorization",
      source_function: "Ledger.request/3"
    },
    %{
      index: 2,
      label: "Dispatch",
      title: "The ledger requests authorization.",
      text:
        "Dispatch marks hold 11 as sent and returns an authorization request for 100¢. That output describes work for the runtime; it does not establish delivery or approval.",
      claim: "po_b3",
      claim_label: "Read the requested-effect claim",
      native_event: {:dispatch, 11},
      next_action: "Let the reply time out",
      source_function: "Ledger.dispatch/2"
    },
    %{
      index: 3,
      label: "Timeout",
      title: "The reply never arrives.",
      text:
        "The processor may have approved the authorization before the reply was lost. The ledger marks the outcome unknown. The 100¢ and its slot stay held.",
      claim: "po_b2",
      claim_label: "Read the capacity-retention claim",
      native_event: {:timeout, 11},
      next_action: "Try another 100¢ request",
      source_function: "Ledger.timeout/2"
    },
    %{
      index: 4,
      label: "Second request",
      title: "The second request is refused.",
      text:
        "Request 12 asks for another 100¢. One slot is free, but the first hold still uses the entire amount limit. The ledger returns insufficient_amount and leaves the account unchanged.",
      claim: "po_a1",
      claim_label: "Read the request-validity claim",
      native_event: {:request, 12, 100},
      next_action: "Start again",
      source_function: "Ledger.request/3"
    }
  ]

  @doc "Compute the five story moments without creating a persisted review session."
  def walkthrough do
    with {:ok, initial} <- TermCodec.encode_state(Ledger.init(100, 2)) do
      start =
        hd(@moments)
        |> Map.merge(%{before: initial, ledger: initial, event: nil, output: nil})

      Enum.reduce_while(tl(@moments), {:ok, [start]}, &compute_moment/2)
    end
  end

  defp compute_moment(moment, {:ok, moments}) do
    before = List.last(moments).ledger

    with {:ok, event} <- TermCodec.encode_event(moment.native_event),
         {:ok, receipt} <- Trace.execute("ledger", before, event) do
      computed =
        Map.merge(moment, %{
          before: receipt["before"],
          ledger: receipt["after"],
          event: receipt["event"],
          output: receipt["output"]
        })

      {:cont, {:ok, moments ++ [computed]}}
    else
      {:error, _} = error -> {:halt, error}
    end
  end

  @doc "Save the selected story prefix only after the user asks to open Case Lab."
  def open_moment(index) when is_integer(index) and index in 0..4 do
    with {:ok, doc} <- Trace.create("ledger", 100, 2),
         {:ok, saved} <- append_prefix(doc, Enum.take(tl(@moments), index)) do
      {:ok, %{doc: saved, slug: Enum.at(@moments, index).claim}}
    end
  end

  def open_moment(_), do: {:error, :unknown_moment}

  defp append_prefix(doc, moments) do
    Enum.reduce_while(moments, {:ok, doc}, fn moment, {:ok, current} ->
      parent = if current["steps"] == [], do: "start", else: List.last(current["steps"])["id"]

      with {:ok, event} <- TermCodec.encode_event(moment.native_event),
           {:ok, updated} <-
             Trace.command(current["id"], current["revision"], Trace.token(), %{
               "kind" => "append",
               "parent" => parent,
               "event" => event
             }) do
        {:cont, {:ok, updated}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  def mutations, do: Enum.filter(Education.examples(), &(&1["kind"] == "mutation"))

  def mutation(id) when is_binary(id) do
    case Enum.find(mutations(), &(&1["id"] == id)) do
      nil ->
        {:error, :unknown_mutation}

      example ->
        path = Enum.find(example["source_paths"], &String.ends_with?(&1, "/mutant.patch"))

        patch =
          with path when is_binary(path) <- path,
               {:ok, text} <- Anchor.read_under(Config.root(), path),
               true <- byte_size(text) <= 64_000 do
            %{path: path, text: text, sha256: Anchor.sha(text)}
          else
            _ -> nil
          end

        {:ok, %{example: example, patch: patch}}
    end
  end

  def mutation(_), do: {:error, :unknown_mutation}

  def source_counts do
    %{
      shared_lean_files:
        length(Path.wildcard(Path.join(Config.root(), "test/support/lean/*.lean")))
    }
  end

  @doc "Read PO-A2's actual contract, implementation excerpts and supplied theorem."
  def translation do
    with {:ok, reading} <- ProofReading.document("po_a2") do
      {:ok,
       %{
         reading: reading,
         implementation: source_excerpt(reading, "lib/hold_ledger/ledger.ex", "def request({"),
         eligibility:
           source_excerpt(reading, "lib/hold_ledger/spec.ex", "def request_eligible?(state,"),
         generated: generated_source(reading)
       }}
    end
  end

  defp source_excerpt(reading, path, selector) do
    with record when is_map(record) <- Enum.find(reading["sources"], &(&1["path"] == path)),
         {:ok, excerpt} <- Anchor.resolve(Config.root(), path, selector, :definition, [path]),
         true <- excerpt.sha256 == record["sha256"] do
      Map.put(excerpt, :url, source_url(reading, record))
    else
      _ -> nil
    end
  end

  @doc "Return an actual matching generated definition excerpt, or no generated source."
  def generated_source(
        %{"focused" => %{"status" => "elaborated", "artifacts" => artifacts}} = reading
      )
      when is_list(artifacts) do
    artifacts
    |> Enum.filter(fn item ->
      path = String.replace(item["path"] || "", "/", ".")

      String.contains?(path, "Elixir.HoldLedger.Ledger") or
        String.contains?(path, "Elixir.HoldLedger.Spec") or
        String.contains?(path, "Elixir.HoldLedger.ProofContracts")
    end)
    |> Enum.find_value(fn item -> generated_excerpt(reading["slug"], item) end)
  end

  def generated_source(_), do: nil

  defp generated_excerpt(slug, item) do
    with {:ok, bytes} <- ProofReading.artifact(slug, item["sha256"]),
         lines = String.split(bytes, "\n"),
         index when is_integer(index) <-
           Enum.find_index(lines, fn line ->
             Regex.match?(
               ~r/^\s*(?:public\s+)?def\s+«(?:request\/3|request_eligible\?\/3|po_a2:requires\/3)»/u,
               line
             )
           end) do
      %{
        path: item["path"],
        sha256: item["sha256"],
        line: index + 1,
        text: lines |> Enum.drop(index) |> Enum.take(32) |> Enum.join("\n"),
        url: "/claims/#{slug}/generated/#{item["sha256"]}"
      }
    else
      _ -> nil
    end
  end

  def source_url(reading, record) when is_map(record),
    do: "/claims/#{reading["slug"]}/source/#{record["id"]}/#{record["sha256"]}"

  def source_url(reading, path) when is_binary(path) do
    case Enum.find(reading["sources"], &(&1["path"] == path)) do
      nil -> nil
      record -> source_url(reading, record)
    end
  end

  def output_term(nil), do: nil

  def output_term(output) do
    case TermCodec.decode_output(output) do
      {:ok, native} -> inspect(native, pretty: true, limit: :infinity)
      _ -> "Output unavailable."
    end
  end
end
