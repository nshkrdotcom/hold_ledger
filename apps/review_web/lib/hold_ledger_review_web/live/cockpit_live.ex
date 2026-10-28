defmodule HoldLedgerReviewWeb.CockpitLive do
  use HoldLedgerReviewWeb, :live_view
  import HoldLedgerReviewWeb.ReviewComponents
  import HoldLedgerReviewWeb.ContrastComponents
  import HoldLedgerReviewWeb.DissectorComponents
  import HoldLedgerReviewWeb.LeanComponents
  import HoldLedgerReviewWeb.ScrubberComponents

  alias HoldLedgerReview.{
    Contrast,
    Part3ContractDelta,
    Part3Docket,
    Part3ProofInspector,
    Part3Runner,
    Part3Snapshots,
    Part3Store,
    ProofReading,
    TermCodec,
    Trace,
    VisualLab
  }

  @impl true
  def mount(_, _, socket) do
    {:ok, catalog} = ProofReading.catalog()

    {:ok,
     assign(socket,
       page_title: "Hold Ledger · Contract review",
       tools: nil,
       advanced: false,
       proof_open: true,
       premises_open: false,
       record_open: false,
       clauses_open: true,
       binding_index: 0,
       selected_evidence: nil,
       inspected: nil,
       premise_key: nil,
       show_sources: false,
       snapshots:
         Enum.map(
           Part3Snapshots.identities(),
           &{"Local snapshot " <> String.slice(&1, 0, 16), &1}
         ),
       catalog: catalog,
       slug: "po_a2",
       reading: nil,
       doc: nil,
       cursor: "start",
       case_data: nil,
       candidate: nil,
       invalid: false,
       basis: "candidate",
       helper: nil,
       stage: 0,
       editor: nil,
       candidate_form: nil,
       initial_form: nil,
       json_form: nil,
       preview: nil,
       fencing: true,
       hunt: %{status: "idle"},
       package_subscription: nil,
       package: nil,
       package_proof: nil,
       delta: %{},
       compare_form: to_form(%{}, as: :compare),
       note_form: to_form(%{}, as: :note),
       event_form: event_form()
     )}
  end

  @impl true
  def handle_params(params, _, socket) do
    slug = params["slug"] || "po_a2"

    case ProofReading.document(slug) do
      {:ok, reading} ->
        socket =
          assign(socket,
            slug: slug,
            inspected: nil,
            premise_key: nil,
            reading: reading,
            stage: 0,
            helper: nil,
            binding_index: 0
          )

        load_session(socket, params["id"])

      _ ->
        {:noreply, put_flash(socket, :error, "Claim source unavailable.")}
    end
  end

  defp load_session(socket, nil) do
    if connected?(socket) do
      case Contrast.create(socket.assigns.slug) do
        {:ok, doc} ->
          {:noreply, push_navigate(socket, to: ~p"/claims/#{socket.assigns.slug}/#{doc["id"]}")}

        _ ->
          {:noreply, put_flash(socket, :error, "Cannot create a source-matching case.")}
      end
    else
      {:noreply, socket}
    end
  end

  defp load_session(socket, id) do
    case Trace.get(id) do
      {:ok, doc} ->
        same = socket.assigns.doc && socket.assigns.doc["id"] == id
        cursor = if same, do: socket.assigns.cursor, else: last_id(doc)
        candidate = if same, do: socket.assigns.candidate

        socket =
          socket
          |> assign(doc: doc, cursor: cursor, candidate: candidate)
          |> refresh_case(candidate)
          |> load_package()

        {:noreply, socket}

      _ ->
        {:noreply, put_flash(socket, :error, "Session unavailable. Open a new case.")}
    end
  end

  @impl true
  def handle_event("law_change", %{"slug" => slug}, %{assigns: %{slug: current}} = socket)
      when slug == current, do: {:noreply, socket}

  def handle_event("law_change", %{"slug" => slug}, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/claims/#{slug}")}

  def handle_event("inspect_law", %{"slug" => slug}, socket),
    do:
      {:noreply,
       push_patch(socket,
         to: ~p"/claims/#{slug}/#{socket.assigns.doc["id"]}"
       )}

  def handle_event("inspect", %{"view" => view}, socket) when view in ~w(proof premises record) do
    key = panel_key(view)

    {:noreply,
     socket |> assign(key, true) |> push_event("focus_evidence", %{id: view <> "-panel"})}
  end

  def handle_event("toggle_panel", %{"panel" => panel}, socket)
      when panel in ~w(proof premises record clauses) do
    key = panel_key(panel)
    {:noreply, assign(socket, key, !socket.assigns[key])}
  end

  def handle_event("open_tools", %{"tool" => tool}, socket) when tool in ~w(draft events) do
    {:noreply, assign(socket, tools: tool, editor: "candidate", advanced: false)}
  end

  def handle_event("close_tools", _, socket), do: {:noreply, assign(socket, tools: nil)}
  def handle_event("show_advanced", _, socket), do: {:noreply, assign(socket, advanced: true)}

  def handle_event("select_evidence", %{"id" => id}, socket) do
    if socket.assigns.package && Enum.any?(socket.assigns.package["evidence"], &(&1["id"] == id)),
      do: {:noreply, assign(socket, selected_evidence: id)},
      else: {:noreply, socket}
  end

  def handle_event("select_binding", %{"index" => index}, socket) do
    with true <- is_binary(index),
         {n, ""} when n >= 0 <- Integer.parse(index),
         data when is_map(data) <- socket.assigns.case_data,
         true <- n < length(data["explanation"]["bindings"]) do
      {:noreply, assign(socket, binding_index: n, helper: nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("inspect_registered_source", %{"id" => id, "sha" => sha}, socket) do
    with source when is_map(source) <-
           Enum.find(socket.assigns.reading["sources"], &(&1["id"] == id && &1["sha256"] == sha)),
         {:ok, bytes} <- ProofReading.source(socket.assigns.slug, id, sha) do
      {:noreply, inspect_source(socket, source["path"], bytes, sha)}
    else
      _ -> {:noreply, error(socket, "Registered source unavailable or stale.")}
    end
  end

  def handle_event("inspect_artifact", %{"sha" => sha}, socket) do
    case ProofReading.artifact(socket.assigns.slug, sha) do
      {:ok, bytes} ->
        {:noreply, inspect_source(socket, "Generated Lean source", bytes, sha)}

      _ ->
        {:noreply, error(socket, "Matching generated source unavailable.")}
    end
  end

  def handle_event("close_source", _, socket), do: {:noreply, assign(socket, inspected: nil)}

  def handle_event("premise_key", %{"key" => key}, socket) do
    case Integer.parse(key) do
      {n, ""} when n in 0..1_000_000 -> {:noreply, assign(socket, premise_key: n)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("open_premise_case", _, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/claims/po_exposure_retain")}

  def handle_event("discard_preview", _, socket),
    do: {:noreply, socket |> assign(preview: nil, hunt: %{status: "idle"}) |> refresh_case(nil)}

  def handle_event("mutate_candidate", %{"kind" => kind}, socket)
      when kind in ~w(drop_effects zero_counters change_identity) do
    case socket.assigns.case_data do
      %{"candidate" => candidate} ->
        output = perturb(candidate, kind)
        {:noreply, refresh_case(socket, output)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cycle_status", %{"index" => index}, socket) do
    with {n, ""} when n >= 0 <- Integer.parse(index),
         %{"candidate" => output} <- socket.assigns.case_data,
         entry when is_map(entry) <- Enum.at(output["after"]["entries"], n) do
      statuses = TermCodec.statuses()

      next =
        Enum.at(
          statuses,
          rem(Enum.find_index(statuses, &(&1 == entry["status"])) + 1, length(statuses))
        )

      {:noreply,
       refresh_case(socket, put_in(output, ["after", "entries", Access.at(n), "status"], next))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("show_sources", _, socket) do
    socket = assign(socket, show_sources: not socket.assigns.show_sources)

    socket =
      if socket.assigns.show_sources,
        do: push_event(socket, "focus_evidence", %{id: "source-comparison"}),
        else: socket

    {:noreply, socket}
  end

  def handle_event("review_decision", params, socket) do
    case socket.assigns.package do
      nil ->
        record_example_decision(socket, params["action"])

      package ->
        with {:ok, command} <-
               Part3Docket.decision(
                 package,
                 params["evidence"],
                 params["action"],
                 Trace.token(),
                 package["human_revision"],
                 "expert",
                 true
               ),
             {:ok, _} <- Part3Store.finding(package["id"], command) do
          {:noreply, load_package(socket)}
        else
          _ ->
            {:noreply,
             error(
               socket,
               "Disposition refused: missing evidence or a newer review revision. Reload before deciding."
             )}
        end
    end
  end

  def handle_event("toggle_assumption", %{"name" => "fencing"}, socket),
    do: {:noreply, assign(socket, fencing: not socket.assigns.fencing)}

  def handle_event("preview_amount", %{"amount" => amount}, socket),
    do: preview_amount(socket, amount)

  def handle_event("boundary", %{"offset" => offset}, socket) when offset in ~w(-1 0 1) do
    case socket.assigns.case_data do
      %{"before" => before} ->
        preview_amount(
          socket,
          to_string(
            max(1, before["amount_limit"] - before["used_amount"] + String.to_integer(offset))
          )
        )

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("apply_preview", _, socket) do
    case socket.assigns.preview do
      nil ->
        {:noreply, socket}

      step ->
        mutate(
          socket,
          %{"kind" => "append", "parent" => step["parent"], "event" => step["event"]},
          true
        )
    end
  end

  def handle_event("hunt", _, socket) do
    case selected(socket.assigns) do
      %{"output" => output} = step when is_map(output) ->
        context = hunt_context(socket)
        slug = socket.assigns.slug

        {:noreply,
         socket
         |> assign(hunt: %{status: "running"})
         |> start_async(:hunt, fn -> {context, VisualLab.hunt(slug, step, 71, 12)} end)}

      _ ->
        {:noreply, assign(socket, hunt: %{status: "unavailable"})}
    end
  end

  def handle_event("cancel_hunt", _, socket),
    do: {:noreply, socket |> cancel_async(:hunt) |> assign(hunt: %{status: "cancelled"})}

  def handle_event("basis", %{"value" => value}, socket) when value in ~w(actual candidate),
    do: {:noreply, assign(socket, basis: value, helper: nil)}

  def handle_event("helper", params, socket) do
    with phase when phase in ~w(requires actual candidate) <- params["phase"],
         true <- is_binary(params["binding"]),
         {binding, ""} when binding >= 0 <- Integer.parse(params["binding"]),
         data when is_map(data) <- socket.assigns.case_data,
         row when is_map(row) <- Enum.at(data["explanation"]["bindings"], binding),
         root when is_map(root) <- row[phase],
         {:ok, node} <- observed_node(root, params["path"]) do
      {:noreply,
       assign(socket, helper: Enum.find(node["children"], &(&1["helper"] != nil)) || node)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_helper", _, socket), do: {:noreply, assign(socket, helper: nil)}

  def handle_event("proof_stage", %{"index" => index}, socket) do
    count = length(socket.assigns.reading["proof_steps"])

    case Integer.parse(index) do
      {i, ""} when i >= 0 and i < count ->
        {:noreply, assign(socket, stage: i)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("lemma", %{"name" => name}, socket) do
    with ref when is_map(ref) <-
           Enum.find(socket.assigns.reading["references"], &(&1["name"] == name)),
         d when is_map(d) <- List.first(ref["declarations"]),
         source when is_map(source) <-
           Enum.find(socket.assigns.reading["sources"], &(&1["path"] == d["path"])),
         {:ok, _bytes} <- ProofReading.source(socket.assigns.slug, source["id"], source["sha256"]) do
      {:noreply, inspect_source(socket, name, d["text"], source["sha256"])}
    else
      _ -> {:noreply, error(socket, "Registered dependency source unavailable or stale.")}
    end
  end

  def handle_event("refresh_evidence", _, socket) do
    case ProofReading.document(socket.assigns.slug) do
      {:ok, doc} -> {:noreply, assign(socket, reading: doc)}
      _ -> {:noreply, error(socket, "Source changed. Restart before reading new evidence.")}
    end
  end

  def handle_event("early_release", _, socket) do
    case selected(socket.assigns) do
      %{"output" => output} = step when is_map(output) ->
        {:noreply, refresh_case(socket, Contrast.early_release(step))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("restore_candidate", _, socket) do
    case selected(socket.assigns) do
      %{"output" => output} when is_map(output) -> {:noreply, refresh_case(socket, output)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("edit_candidate", _, socket),
    do: {:noreply, assign(socket, tools: "draft", editor: "candidate", advanced: false)}

  def handle_event("candidate_change", %{"output" => params}, socket),
    do: candidate_input(socket, params)

  def handle_event("check_candidate", %{"output" => params}, socket),
    do: candidate_input(socket, params)

  def handle_event("candidate_json", %{"json" => json}, socket) when byte_size(json) <= 64_000 do
    with {:ok, output} <- Jason.decode(json), {:ok, _} <- TermCodec.decode_output(output) do
      {:noreply, refresh_case(socket, output)}
    else
      _ ->
        {:noreply,
         socket |> assign(invalid: true, case_data: nil) |> error("Invalid typed output JSON.")}
    end
  end

  def handle_event("candidate_recalculate", _, socket) do
    with {:ok, output} <- Contrast.parse_output(socket.assigns.candidate_form.params),
         {:ok, state} <- TermCodec.decode_state(output["after"]) do
      entries = elem(state, 4)

      output =
        output
        |> put_in(["after", "used_amount"], HoldLedger.Spec.hold_amount(entries))
        |> put_in(["after", "used_holds"], HoldLedger.Spec.hold_count(entries))

      {:noreply, refresh_case(socket, output)}
    else
      _ -> {:noreply, error(socket, "Correct the fields before recalculating.")}
    end
  end

  def handle_event("candidate_add_entry", _, socket) do
    params = socket.assigns.candidate_form.params
    entries = params["entries"] || %{}

    if map_size(entries) < 8 do
      params =
        Map.put(
          params,
          "entries",
          Map.put(entries, to_string(map_size(entries)), %{
            "key" => "2",
            "amount" => "1",
            "status" => "reserved"
          })
        )

      candidate_input(socket, params)
    else
      {:noreply, error(socket, "Eight entries maximum.")}
    end
  end

  def handle_event("candidate_add_effect", _, socket) do
    params = socket.assigns.candidate_form.params
    effects = params["effects"] || %{}

    candidate_input(
      socket,
      Map.put(
        params,
        "effects",
        Map.put(effects, to_string(map_size(effects)), %{
          "type" => "void",
          "key" => "1",
          "amount" => "1"
        })
      )
    )
  end

  def handle_event("candidate_clear_effects", _, socket),
    do: candidate_input(socket, Map.put(socket.assigns.candidate_form.params, "effects", %{}))

  def handle_event("branch_candidate", _, %{assigns: %{preview: preview}} = socket)
      when is_map(preview),
      do:
        {:noreply,
         error(
           socket,
           "Save or discard the active scratch case before recording a hypothetical branch."
         )}

  def handle_event("branch_candidate", _, socket) do
    case socket.assigns.case_data do
      %{"candidate_valid" => true, "candidate" => output} ->
        mutate(
          socket,
          %{"kind" => "candidate", "parent" => socket.assigns.cursor, "output" => output},
          true
        )

      _ ->
        {:noreply, error(socket, "The hypothetical state must be valid before continuing.")}
    end
  end

  def handle_event("save_challenge", _, %{assigns: %{preview: preview}} = socket)
      when is_map(preview),
      do: {:noreply, error(socket, "Add the preview to the trace first.")}

  def handle_event("save_challenge", _, socket) do
    if socket.assigns.case_data do
      mutate(
        socket,
        %{
          "kind" => "challenge",
          "step" => socket.assigns.cursor,
          "slug" => socket.assigns.slug,
          "output" => socket.assigns.case_data["candidate"]
        },
        false
      )
    else
      {:noreply, error(socket, "No valid typed candidate to save.")}
    end
  end

  def handle_event("edit_initial", _, socket) do
    {:ok, json} = Trace.state_at(socket.assigns.doc, socket.assigns.cursor)
    params = Map.update!(json, "entries", &Contrast.indexed/1)

    {:noreply,
     assign(socket,
       initial_form: to_form(params, as: :initial),
       tools: "initial",
       editor: "initial"
     )}
  end

  def handle_event("initial_change", %{"initial" => params}, socket),
    do: {:noreply, assign(socket, initial_form: to_form(params, as: :initial))}

  def handle_event("initial_add_entry", _, socket) do
    params = socket.assigns.initial_form.params
    entries = params["entries"] || %{}

    if map_size(entries) < 8 do
      {:noreply,
       assign(socket,
         initial_form:
           to_form(
             Map.put(
               params,
               "entries",
               Map.put(entries, to_string(map_size(entries)), %{
                 "key" => "2",
                 "amount" => "1",
                 "status" => "reserved"
               })
             ),
             as: :initial
           )
       )}
    else
      {:noreply, error(socket, "Eight entries maximum.")}
    end
  end

  def handle_event("initial_recalculate", _, socket) do
    with {:ok, json} <- Contrast.parse_state(socket.assigns.initial_form.params),
         {:ok, state} <- TermCodec.decode_state(json) do
      params =
        socket.assigns.initial_form.params
        |> Map.put("used_amount", HoldLedger.Spec.hold_amount(elem(state, 4)))
        |> Map.put("used_holds", HoldLedger.Spec.hold_count(elem(state, 4)))

      {:noreply, assign(socket, initial_form: to_form(params, as: :initial))}
    else
      _ -> {:noreply, error(socket, "Correct the fields first.")}
    end
  end

  def handle_event("save_initial", %{"initial" => params}, socket) do
    with {:ok, json} <- Contrast.parse_state(params), {:ok, doc} <- Trace.create_from(json) do
      {:noreply, push_navigate(socket, to: ~p"/claims/#{socket.assigns.slug}/#{doc["id"]}")}
    else
      _ ->
        {:noreply,
         socket
         |> assign(initial_form: to_form(params, as: :initial))
         |> error(
           "Starting state must have unique entries and matching counters within both limits."
         )}
    end
  end

  def handle_event("select_step", %{"id" => id}, socket), do: select_step(socket, id)

  def handle_event("event_change", %{"event" => params}, socket),
    do:
      {:noreply,
       assign(socket,
         event_form: to_form(Map.merge(socket.assigns.event_form.params, params), as: :event)
       )}

  def handle_event("apply_event", _, %{assigns: %{preview: preview}} = socket)
      when is_map(preview),
      do:
        {:noreply,
         error(socket, "Save or discard the active scratch case before recording another event.")}

  def handle_event("apply_event", %{"event" => params}, socket) do
    case event_json(socket.assigns.doc["mode"], params) do
      {:ok, json} ->
        socket = assign(socket, event_form: to_form(params, as: :event))

        mutate(
          socket,
          %{"kind" => "append", "parent" => socket.assigns.cursor, "event" => json},
          true
        )

      _ ->
        {:noreply, error(socket, "Invalid event fields.")}
    end
  end

  def handle_event("coupled", _, socket) do
    case Trace.create("exposure") do
      {:ok, doc} ->
        {:noreply, push_navigate(socket, to: ~p"/claims/po_exposure_model/#{doc["id"]}")}

      _ ->
        {:noreply, error(socket, "Cannot create coupled model.")}
    end
  end

  def handle_event("record_note", %{"note" => params}, socket),
    do:
      mutate(
        socket,
        %{
          "kind" => "note",
          "step" => socket.assigns.cursor,
          "text" => params["text"],
          "disposition" => "concern"
        },
        false
      )

  def handle_event("compare", %{"compare" => params}, socket) do
    case Part3Store.create(params["baseline"], params["proposal"]) do
      {:ok, package} ->
        mutate(
          assign(socket, show_sources: false),
          %{"kind" => "comparison", "id" => package["id"]},
          false
        )

      _ ->
        {:noreply, error(socket, "Compatible locally staged snapshots required.")}
    end
  end

  def handle_event("pair_proof", _, socket) do
    case Part3ProofInspector.inspect(socket.assigns.package) do
      {:ok, proof} ->
        {:noreply,
         socket
         |> assign(package_proof: proof)
         |> put_flash(
           :info,
           "Pair artifacts loaded: #{length(proof["versions"])} source versions."
         )}

      {:error, reason} ->
        {:noreply, error(socket, "Matching proof artifacts unavailable: #{inspect(reason)}")}
    end
  end

  def handle_event("replay", _, socket) do
    with package when is_map(package) <- socket.assigns.package,
         case_data when is_map(case_data) <- socket.assigns.case_data,
         witness = %{
           "before" => case_data["before"],
           "event" => case_data["event"],
           "output" => case_data["candidate"],
           "follow_on" => nil
         },
         {:ok, _} <- Part3Runner.replay(package["id"], witness) do
      {:noreply, load_package(socket)}
    else
      _ -> {:noreply, error(socket, "Select a typed ledger case and a compatible source pair.")}
    end
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    _ = Part3Runner.cancel(socket.assigns.package["id"], id)
    {:noreply, load_package(socket)}
  end

  def handle_event(_, _, socket), do: {:noreply, error(socket, "Unknown action.")}

  @impl true
  def handle_async(:hunt, {:ok, _}, %{assigns: %{hunt: %{status: "cancelled"}}} = socket),
    do: {:noreply, socket}

  def handle_async(:hunt, {:ok, {context, result}}, socket) do
    if socket.assigns.hunt.status == "running" and context == hunt_context(socket) and
         Trace.current?(socket.assigns.doc) do
      socket =
        if result.status == "found",
          do: socket |> refresh_case(result.output) |> assign(basis: "candidate"),
          else: socket

      {:noreply, assign(socket, hunt: result)}
    else
      {:noreply, assign(socket, hunt: %{status: "stale"})}
    end
  end

  def handle_async(:hunt, {:exit, _}, socket) do
    status = if socket.assigns.hunt.status == "cancelled", do: "cancelled", else: "failed"
    {:noreply, assign(socket, hunt: %{status: status})}
  end

  defp panel_key("proof"), do: :proof_open
  defp panel_key("premises"), do: :premises_open
  defp panel_key("record"), do: :record_open
  defp panel_key("clauses"), do: :clauses_open

  defp observed_node(root, path) when is_binary(path) and byte_size(path) <= 300 do
    parts = if path == "", do: [], else: String.split(path, ".")

    Enum.reduce_while(parts, {:ok, root}, fn index, {:ok, node} ->
      with {n, ""} when n >= 0 <- Integer.parse(index),
           child when is_map(child) <- Enum.at(node["children"], n) do
        {:cont, {:ok, child}}
      else
        _ -> {:halt, :error}
      end
    end)
  end

  defp observed_node(_, _), do: :error

  defp record_example_decision(socket, action) when action in ~w(design policy considered) do
    label =
      %{
        "design" => "Request repair",
        "policy" => "Needs policy/evidence decision",
        "considered" => "Considered in scope"
      }[action]

    input =
      if socket.assigns.case_data,
        do: Jason.encode!(socket.assigns.case_data["event"]),
        else: "no executable case"

    text =
      "Example review: #{label}. Law #{socket.assigns.slug}; input #{input}. Scoped local concern; no policy authorization or formal acceptance."

    doc = socket.assigns.doc

    command = %{
      "kind" => "note",
      "step" => socket.assigns.cursor,
      "text" => text,
      "disposition" => "concern"
    }

    case Trace.command(doc["id"], doc["revision"], Trace.token(), command) do
      {:ok, updated} ->
        {:noreply, assign(socket, doc: updated)}

      _ ->
        {:noreply,
         error(socket, "Another tab changed this record. Reload before recording a disposition.")}
    end
  end

  defp record_example_decision(socket, _), do: {:noreply, error(socket, "Unknown review action.")}

  defp perturb(output, "drop_effects"), do: Map.put(output, "effects", [])

  defp perturb(output, "zero_counters"),
    do: output |> put_in(["after", "used_amount"], 0) |> put_in(["after", "used_holds"], 0)

  defp perturb(output, "change_identity") do
    update_in(output, ["after", "entries"], fn
      [] -> []
      [entry | rest] -> [Map.put(entry, "key", rem(entry["key"] + 1, 1_000_001)) | rest]
    end)
  end

  defp hunt_context(socket),
    do:
      {socket.assigns.doc["id"], socket.assigns.doc["revision"], socket.assigns.cursor,
       socket.assigns.slug, socket.assigns.preview}

  defp preview_amount(socket, amount) do
    with {n, ""} when n in 1..1_000_000 <- Integer.parse(amount),
         step when is_map(step) <- selected(socket.assigns),
         %{"type" => "request"} = event <- step["event"],
         {:ok, receipt} <- Trace.execute("ledger", step["before"], Map.put(event, "amount", n)) do
      preview = Map.merge(step, receipt) |> Map.put("id", "preview")
      {:noreply, socket |> assign(preview: preview, hunt: %{status: "idle"}) |> refresh_case(nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:part3_updated, _}, socket), do: {:noreply, load_package(socket)}

  defp candidate_input(socket, params) do
    case Contrast.parse_output(params) do
      {:ok, output} ->
        {:noreply,
         socket |> refresh_case(output) |> assign(candidate_form: to_form(params, as: :output))}

      _ ->
        {:noreply,
         assign(socket,
           candidate_form: to_form(params, as: :output),
           invalid: true,
           case_data: nil,
           helper: nil
         )}
    end
  end

  defp refresh_case(socket, candidate) do
    case Contrast.case_for(
           evaluation_doc(socket.assigns),
           if(socket.assigns.preview, do: "preview", else: socket.assigns.cursor),
           socket.assigns.slug,
           candidate
         ) do
      {:ok, data} ->
        assign(socket,
          case_data: data,
          candidate: data["candidate"],
          candidate_form: to_form(Contrast.output_form(data["candidate"]), as: :output),
          invalid: false,
          helper: nil
        )

      _ ->
        assign(socket,
          case_data: nil,
          candidate: nil,
          candidate_form: nil,
          invalid: false,
          helper: nil
        )
    end
  end

  defp select_step(socket, id) do
    if id == "start" or Trace.step(socket.assigns.doc, id),
      do:
        {:noreply,
         socket
         |> assign(cursor: id, editor: nil, preview: nil, hunt: %{status: "idle"})
         |> refresh_case(nil)},
      else: {:noreply, socket}
  end

  defp inspect_source(socket, name, bytes, sha) do
    socket
    |> assign(inspected: %{name: name, bytes: bytes, sha: sha}, proof_open: true)
    |> push_event("focus_evidence", %{id: "inline-source"})
  end

  defp mutate(socket, action, move?) do
    doc = socket.assigns.doc

    case Trace.command(doc["id"], doc["revision"], Trace.token(), action) do
      {:ok, updated} ->
        cursor = if move?, do: command_cursor(updated, action), else: socket.assigns.cursor
        socket = assign(socket, doc: updated, cursor: cursor, hunt: %{status: "idle"})

        socket =
          if move?,
            do: socket |> assign(preview: nil) |> refresh_case(nil),
            else: socket

        {:noreply, load_package(socket)}

      {:error, :revision_conflict} ->
        {:noreply, error(socket, "Another tab changed this session. Reload before saving.")}

      {:error, reason} ->
        {:noreply, error(socket, "Refused: #{reason}")}
    end
  end

  defp command_cursor(doc, %{"kind" => "append", "parent" => parent, "event" => event}),
    do:
      Enum.find(
        doc["steps"],
        &(&1["parent"] == parent and &1["event"] == event and not Map.has_key?(&1, "challenge_of"))
      )["id"]

  defp command_cursor(doc, %{"kind" => "candidate", "parent" => parent, "output" => output}),
    do: Enum.find(doc["steps"], &(&1["challenge_of"] == parent and &1["output"] == output))["id"]

  defp load_package(socket) do
    id = socket.assigns.doc["comparison"]

    if id do
      socket = subscribe_package(socket, id)

      case Part3Store.get(id) do
        {:ok, package, :ok} ->
          {:ok, delta} = Part3ContractDelta.presentation(package)
          assign(socket, package: package, delta: delta)

        _ ->
          assign(socket, package: nil)
      end
    else
      socket
    end
  end

  defp subscribe_package(socket, id) do
    if connected?(socket) && socket.assigns.package_subscription != id do
      if old = socket.assigns.package_subscription,
        do: Phoenix.PubSub.unsubscribe(HoldLedgerReview.PubSub, "part3:" <> old)

      :ok = Phoenix.PubSub.subscribe(HoldLedgerReview.PubSub, "part3:" <> id)
      assign(socket, package_subscription: id, package_proof: nil)
    else
      socket
    end
  end

  defp evaluation_doc(%{preview: nil} = assigns), do: assigns.doc
  defp evaluation_doc(assigns), do: Map.update!(assigns.doc, "steps", &(&1 ++ [assigns.preview]))

  defp selected(%{preview: preview}) when is_map(preview), do: preview
  defp selected(assigns), do: if(assigns.doc, do: Trace.step(assigns.doc, assigns.cursor))
  defp last_id(doc), do: if(doc["steps"] == [], do: "start", else: List.last(doc["steps"])["id"])

  defp error(socket, text), do: put_flash(socket, :error, text)

  defp event_form,
    do:
      to_form(%{"type" => "request", "key" => "2", "amount" => "100", "outcome" => "approved"},
        as: :event
      )

  defp event_json(mode, params) do
    with {key, ""} <- Integer.parse(params["key"] || "0"),
         {amount, ""} <- Integer.parse(params["amount"] || "1"),
         {:ok, native} <- native_event(params["type"], key, amount, params["outcome"]) do
      if mode == "ledger",
        do: TermCodec.encode_event(native),
        else: exposure_event(params["type"], native, key, params["outcome"])
    else
      _ -> {:error, :invalid_event}
    end
  end

  defp native_event("request", key, amount, _), do: {:ok, {:request, key, amount}}
  defp native_event("restart", _, _, _), do: {:ok, :restart}

  defp native_event("processor_result", key, _, "approved"),
    do: {:ok, {:processor_result, key, :approved}}

  defp native_event("processor_result", key, _, "declined"),
    do: {:ok, {:processor_result, key, :declined}}

  defp native_event(type, key, _, _) do
    case Enum.find(
           [
             :dispatch,
             :timeout,
             :retry,
             :transport_ack,
             :void,
             :void_confirmed,
             :observe,
             :confirm,
             :authorize,
             :remote_void
           ],
           &(Atom.to_string(&1) == type)
         ) do
      nil -> {:error, :invalid_event}
      atom -> {:ok, {atom, key}}
    end
  end

  defp exposure_event("authorize", _, key, "approved"),
    do: TermCodec.encode_exposure_event({:authorize, key, :approved})

  defp exposure_event("authorize", _, key, "declined"),
    do: TermCodec.encode_exposure_event({:authorize, key, :declined})

  defp exposure_event("remote_void", _, key, _), do: TermCodec.encode_exposure_event({:void, key})

  defp exposure_event(type, event, _, _) when type in ~w(observe confirm),
    do: TermCodec.encode_exposure_event(event)

  defp exposure_event(_, event, _, _), do: TermCodec.encode_exposure_event({:local, event})

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section :if={!@doc} aria-label="Opening review">
        <h1>Review guarantee</h1><p role="status">Opening a source-bound case…</p>
      </section>
      <div :if={@doc && @reading} id="review-document">
        <header class="review-bar">
          <div class="review-heading">
            <h1>Review guarantee</h1><.form
              for={to_form(%{"slug" => @slug})}
              id="law-picker"
              phx-change="law_change"
            >
              <.input
                name="slug"
                value={@slug}
                type="select"
                label="Law under review"
                options={Enum.map(@catalog, &{&1["title"], &1["slug"]})}
              />
            </.form><div class="history-actions">
              <button
                id="append-preview"
                phx-click="apply_preview"
                disabled={!@preview}
                class="record-action"
              >Save case</button><button
                id="record-event"
                phx-click="open_tools"
                phx-value-tool="events"
              >Record event…</button>
            </div>
          </div>
          <.disposition package={@package} doc={@doc} selected_evidence={@selected_evidence} />
        </header>
        <p :if={!Trace.current?(@doc)} role="alert" id="stale-session">
          Session source changed. Results cannot be used as current evidence.
        </p>
        <div id="review-workspace">
          <.comparison
            reading={@reading}
            case={@case_data}
            step={selected(assigns)}
            package={@package}
            delta={@delta}
            preview={@preview}
            compare_form={@compare_form}
            snapshots={@snapshots}
            show_sources={@show_sources}
            doc={@doc}
          />
          <.timeline doc={@doc} cursor={@cursor} preview={@preview} />
          <section class="case-layout" aria-label="Active case and findings">
            <div class="active-case" id="active-case">
              <.active_state doc={@doc} cursor={@cursor} step={selected(assigns)} /><.input_strip
                case={@case_data}
                preview={@preview}
              /><p :if={@preview} class="scratch-label" id="scratch-status">
                Unsaved case · history unchanged <button phx-click="discard_preview">Discard</button>
              </p><.contrast
                case={@case_data}
                step={selected(assigns)}
                slug={@slug}
                invalid={@invalid}
              />
            </div>
            <aside class="case-findings" id="case-findings">
              <h2>What this case shows</h2><.pair_results
                case={@case_data}
                reading={@reading}
                step={selected(assigns)}
                package={@package}
                preview={nil}
              /><.verdict case={@case_data} slug={@slug} /><p class="scope-note">
                Full formal acceptance: {@reading["formal"]["status"]}. Concrete results do not establish universal acceptance.
              </p><nav class="evidence-links" id="inspector-tools">
                <button
                  :for={
                    {view, label} <- [
                      {"proof", "Proof source"},
                      {"premises", "External premises"},
                      {"record", "Review notes"}
                    ]
                  }
                  phx-click="inspect"
                  phx-value-view={view}
                >{label} ↓</button>
              </nav>
            </aside>
          </section>
          <details id="clauses-panel" class="evidence-panel" open={@clauses_open}>
            <summary phx-click="toggle_panel" phx-value-panel="clauses">Clause evidence</summary><.dissector
              reading={@reading}
              case={@case_data}
              basis={@basis}
              helper={@helper}
              binding_index={@binding_index}
            />
          </details>
          <details id="proof-panel" class="evidence-panel" open={@proof_open}>
            <summary phx-click="toggle_panel" phx-value-panel="proof">
              Proof source and dependencies
            </summary><.proof_source reading={@reading} stage={@stage} /><section
              :if={@inspected}
              id="inline-source"
              class="inline-source"
            >
              <header>
                <h3>{@inspected.name}</h3><button phx-click="close_source">Close source</button>
              </header><small>SHA-256 {@inspected.sha}</small><pre>{@inspected.bytes}</pre>
            </section><button :if={@package} phx-click="pair_proof" id="pair-proof">Inspect pair proof artifacts</button><.pair_artifacts
              :if={@package_proof}
              proof={@package_proof}
              package={@package}
              slug={@slug}
            />
          </details>
          <details id="premises-panel" class="evidence-panel" open={@premises_open}>
            <summary phx-click="toggle_panel" phx-value-panel="premises">
              External assumptions
            </summary><.premise case={@case_data} fencing={@fencing} selected_key={@premise_key} /><.assumptions
              reading={@reading}
              show_status={false}
            />
          </details>
          <details id="record-panel" class="evidence-panel" open={@record_open}>
            <summary phx-click="toggle_panel" phx-value-panel="record">
              Review history and notes
            </summary><section id="session-record">
              <h2>Review record</h2><a href={~p"/sessions/#{@doc["id"]}/export"}>Download session</a><button
                phx-click="save_challenge"
                disabled={!@case_data || @preview != nil}
              >Save recorded-input challenge</button><span>{length(@doc["challenges"])} saved challenges</span><.form
                for={@note_form}
                id="note-form"
                phx-submit="record_note"
              >
                <.input field={@note_form[:text]} type="textarea" label="Review note" /><button>Record concern</button>
              </.form>
            </section><.review_history package={@package} doc={@doc} />
          </details>
        </div>
      </div>
      <div :if={@tools} class="tool-overlay">
        <div class="tool-backdrop" phx-click="close_tools" aria-hidden="true"></div>
        <aside
          id="tool-drawer"
          class="tool-drawer"
          phx-hook="ToolDrawer"
          role="dialog"
          aria-modal="true"
          aria-labelledby="tool-title"
        >
          <header class="drawer-header">
            <div>
              <h2 id="tool-title">
                {case @tools do
                  "draft" -> "Change drafted outcome"
                  "events" -> "Record an event"
                  _ -> "Edit starting state"
                end}
              </h2><p :if={@tools == "draft" && @case_data} id="drawer-verdict">
                Accounting: {@case_data["candidate_valid"]} · {@slug}: {@case_data["law_status"]}
              </p>
            </div><button id="close-tools" phx-click="close_tools">Close</button>
          </header>
          <div class="drawer-body">
            <div :if={@tools == "draft"}>
              <.draft_tools case={@case_data} step={selected(assigns)} preview={@preview} /><div class="candidate-search">
                <button
                  phx-click="hunt"
                  id="hunt-candidate"
                  disabled={!@case_data || @hunt.status == "running"}
                >Try six output variations</button><button
                  :if={@hunt.status == "running"}
                  phx-click="cancel_hunt"
                >Cancel search</button><output id="hunt-status">{@hunt.status}{if @hunt[:cases],
                  do: " · #{@hunt.cases} cases · #{@hunt.elapsed_ms}ms · seed #{@hunt.seed}"}</output>
              </div><.editors
                :if={@advanced}
                case={@case_data}
                editor="candidate"
                candidate_form={@candidate_form}
                initial_form={@initial_form}
              />
            </div><.event_controls
              :if={@tools == "events"}
              builder_open={true}
              doc={@doc}
              event_form={@event_form}
              step={selected(assigns)}
              preview={@preview}
            /><.editors
              :if={@tools == "initial"}
              case={@case_data}
              editor="initial"
              candidate_form={@candidate_form}
              initial_form={@initial_form}
            />
          </div>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
