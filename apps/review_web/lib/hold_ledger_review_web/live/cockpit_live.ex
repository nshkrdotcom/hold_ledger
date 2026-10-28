defmodule HoldLedgerReviewWeb.CockpitLive do
  use HoldLedgerReviewWeb, :live_view
  import HoldLedgerReviewWeb.ReviewComponents
  import HoldLedgerReviewWeb.ContrastComponents
  import HoldLedgerReviewWeb.DissectorComponents
  import HoldLedgerReviewWeb.LeanComponents
  import HoldLedgerReviewWeb.ScrubberComponents

  alias HoldLedgerReviewWeb.{Experiment, ReviewCopy}
  alias HoldLedgerReview.ProofReading.Links

  alias HoldLedgerReview.{
    Canonical,
    Contrast,
    Part3ContractDelta,
    Part3Docket,
    Part3ProofInspector,
    Part3RepairPacket,
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
       secondary: nil,
       proof_full: false,
       experiment: nil,
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
       selection: nil,
       note_open: false,
       repair_status: %{status: "unavailable", reason: "No comparison evidence"},
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
  def handle_params(
        %{"pane" => pane, "id" => id, "slug" => slug},
        _,
        %{assigns: %{doc: %{"id" => current}, slug: current_slug}} = socket
      )
      when id == current and slug == current_slug and pane in ~w(premises record artifacts),
      do: {:noreply, assign(socket, secondary: pane)}

  def handle_params(params, _, socket) do
    slug = params["slug"] || "po_a2"

    case ProofReading.document(slug) do
      {:ok, reading} ->
        socket =
          assign(socket,
            slug: slug,
            secondary: if(params["pane"] in ~w(premises record artifacts), do: params["pane"]),
            inspected: nil,
            premise_key: nil,
            reading: reading,
            stage: 0,
            helper: nil,
            binding_index: 0,
            selection: nil
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
          |> assign(
            doc: doc,
            cursor: cursor,
            candidate: candidate,
            experiment: if(same, do: socket.assigns.experiment),
            preview: if(same, do: socket.assigns.preview)
          )
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

  def handle_event("inspect", %{"view" => view}, socket)
      when view in ~w(proof clauses premises record artifacts) do
    if view in ~w(proof clauses) do
      {:noreply, push_event(socket, "focus_evidence", %{id: view <> "-panel"})}
    else
      {:noreply,
       socket
       |> assign(secondary: view)
       |> push_patch(
         to: ~p"/claims/#{socket.assigns.slug}/#{socket.assigns.doc["id"]}?pane=#{view}"
       )
       |> push_event("focus_evidence", %{id: view <> "-panel"})}
    end
  end

  def handle_event("full_proof", _, socket),
    do: {:noreply, assign(socket, proof_full: !socket.assigns.proof_full)}

  def handle_event("reset_experiment", _, socket) do
    {:noreply,
     socket
     |> assign(experiment: nil, preview: nil, cursor: last_id(socket.assigns.doc))
     |> refresh_case(nil)}
  end

  def handle_event("alternative_total", %{"amount" => amount}, socket) do
    if socket.assigns.candidate_form do
      candidate_input(
        socket,
        Map.put(socket.assigns.candidate_form.params, "used_amount", amount)
      )
    else
      {:noreply, socket}
    end
  end

  def handle_event("open_tools", %{"tool" => tool}, socket) when tool in ~w(draft events) do
    {:noreply, assign(socket, tools: tool, editor: "candidate", advanced: false)}
  end

  def handle_event("close_tools", _, socket), do: {:noreply, assign(socket, tools: nil)}
  def handle_event("show_advanced", _, socket), do: {:noreply, assign(socket, advanced: true)}

  def handle_event("select_evidence", %{"id" => id}, socket) do
    if socket.assigns.package && Enum.any?(socket.assigns.package["evidence"], &(&1["id"] == id)),
      do: {:noreply, socket |> assign(selected_evidence: id) |> repair_availability()},
      else: {:noreply, socket}
  end

  def handle_event("select_binding", %{"index" => index}, socket) do
    with true <- is_binary(index),
         {n, ""} when n >= 0 <- Integer.parse(index),
         data when is_map(data) <- socket.assigns.case_data,
         true <- n < length(data["explanation"]["bindings"]) do
      {:noreply, assign(socket, binding_index: n, helper: nil, selection: nil)}
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
    case prepare_experiment(socket) do
      {:ok, exp} -> save_experiment(socket, exp)
      {:error, reason} -> {:noreply, error(socket, "Cannot save this experiment: #{reason}.")}
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
    do: {:noreply, assign(socket, basis: value, helper: nil, selection: nil)}

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

    case if(is_binary(index), do: Integer.parse(index), else: :error) do
      {i, ""} when i >= 0 and i < count ->
        links = current_links(socket).links
        socket = assign(socket, stage: i, selection: %{type: :step, index: i})

        case Enum.find(links, &(i in &1["steps"])) do
          nil -> {:noreply, socket}
          link -> {:noreply, push_event(socket, "focus_evidence", %{id: clause_id(link)})}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_clause", params, socket) do
    phase = params["phase"]

    with true <- is_binary(params["generation"]),
         true <- params["generation"] == socket.assigns.reading["source_generation"],
         true <- phase in ["requires", socket.assigns.basis],
         true <- is_binary(params["binding"]),
         {n, ""} <- Integer.parse(params["binding"]),
         true <- n == socket.assigns.binding_index,
         data when is_map(data) <- socket.assigns.case_data,
         row when is_map(row) <- Enum.at(data["explanation"]["bindings"], n),
         root when is_map(root) <- row[phase],
         {:ok, _node} <- observed_node(root, params["path"]) do
      path = params["path"]
      selected = %{type: :clause, binding: n, phase: phase, path: path,
                   basis: socket.assigns.basis, generation: socket.assigns.reading["source_generation"]}
      links = Enum.filter(current_links(socket).links, &(&1["phase"] == phase and &1["path"] == path))
      socket = assign(socket, selection: selected)

      case links do
        [first | _] ->
          {:noreply,
           socket
           |> assign(stage: hd(first["steps"]))
           |> push_event("focus_evidence", %{id: "proof-source-workspace"})}

        _ -> {:noreply, socket}
      end
    else
      _ -> {:noreply, error(socket, "Clause selection is stale or unavailable for these values.")}
    end
  end

  defp current_links(socket),
    do:
      Links.project(
        socket.assigns.reading,
        socket.assigns.case_data,
        socket.assigns.binding_index,
        socket.assigns.basis
      )

  defp clause_id(link),
    do:
      "clause-#{link["binding"]}-#{link["phase"]}-#{if(link["path"] == "", do: "root", else: String.replace(link["path"], ".", "-"))}"

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
         socket
         |> assign(invalid: true, case_data: nil, selection: nil)
         |> repair_availability()
         |> error("Invalid typed output JSON.")}
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

  def handle_event("branch_candidate", _, socket) do
    case socket.assigns.case_data do
      %{"candidate_valid" => true, "candidate" => output} ->
        run_experiment(socket, fn exp ->
          %{"kind" => "candidate", "parent" => exp.cursor, "output" => output}
        end)

      _ ->
        {:noreply,
         error(socket, "Correct the alternative's accounting before continuing from it.")}
    end
  end

  def handle_event("save_challenge", _, %{assigns: %{preview: preview}} = socket)
      when is_map(preview),
      do:
        {:noreply, error(socket, "Save the experiment first to attach this case to your review.")}

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

  def handle_event("apply_event", %{"event" => params}, socket) do
    case event_json(socket.assigns.doc["mode"], params) do
      {:ok, json} ->
        socket = assign(socket, event_form: to_form(params, as: :event))

        run_experiment(socket, fn exp ->
          %{"kind" => "append", "parent" => exp.cursor, "event" => json}
        end)

      _ ->
        {:noreply, error(socket, "Enter a valid event, identity and amount.")}
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

  def handle_event("toggle_note", _, socket),
    do: {:noreply, assign(socket, note_open: not socket.assigns.note_open)}

  def handle_event("record_note", %{"note" => %{"text" => text}}, socket) when is_binary(text) do
    case mutate(socket, note_action(socket.assigns, text), false) do
      {:noreply, updated} ->
        if updated.assigns.doc["revision"] != socket.assigns.doc["revision"],
          do: {:noreply, assign(updated, note_open: false, note_form: to_form(%{}, as: :note))},
          else: {:noreply, updated}
    end
  end

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
         |> assign(package_proof: proof, secondary: "artifacts")
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

  defp note_action(assigns, text) do
    anchor = if Trace.step(assigns.doc, assigns.cursor), do: assigns.cursor, else: "start"

    text =
      if assigns.preview || assigns.experiment, do: experiment_note(assigns, text), else: text

    %{"kind" => "note", "step" => anchor, "text" => text, "disposition" => "concern"}
  end

  defp experiment_note(assigns, text) do
    digest =
      HoldLedgerReview.Canonical.digest(%{
        "step" => selected(assigns),
        "alternative" => assigns.candidate
      })

    text <> "\nUnsaved experiment: " <> digest <> ". Save the experiment to retain its steps."
  end

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
      "Example review: #{label}. Law #{socket.assigns.slug}; input #{input}. "

    doc = socket.assigns.doc

    command = note_action(socket.assigns, text)

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
       socket.assigns.slug, socket.assigns.preview, socket.assigns.experiment}

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
         socket
         |> assign(
           candidate_form: to_form(params, as: :output),
           invalid: true,
           case_data: nil,
           helper: nil,
           selection: nil
         )
         |> repair_availability()}
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
        socket
        |> assign(
          case_data: data,
          candidate: data["candidate"],
          candidate_form: to_form(Contrast.output_form(data["candidate"]), as: :output),
          invalid: false,
          helper: nil,
          selection: nil
        )
        |> repair_availability()

      _ ->
        socket
        |> assign(
          case_data: nil,
          candidate: nil,
          candidate_form: nil,
          invalid: false,
          helper: nil,
          selection: nil
        )
        |> repair_availability()
    end
  end

  defp select_step(socket, id) do
    if id == "start" or Trace.step(experiment_doc(socket.assigns), id),
      do:
        {:noreply,
         socket
         |> assign(cursor: id, editor: nil, preview: nil, hunt: %{status: "idle"})
         |> refresh_case(nil)},
      else: {:noreply, socket}
  end

  defp inspect_source(socket, name, bytes, sha) do
    socket
    |> assign(inspected: %{name: name, bytes: bytes, sha: sha})
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
          socket |> assign(package: package, delta: delta) |> repair_availability()

        _ ->
          assign(socket, package: nil, delta: %{}, repair_status: %{status: "unavailable", reason: "Comparison unavailable"})
      end
    else
      assign(socket, package: nil, delta: %{}, repair_status: %{status: "unavailable", reason: "No comparison evidence"})
    end
  end

  # A packet describes one immutable comparison evidence item. Merely opening a
  # trace linked to a source pair does not make that evidence about the active
  # (potentially unsaved and repeatedly edited) output. Keep the historical
  # evidence selectable but never present it as this case's result.
  defp repair_availability(socket) do
    package = socket.assigns.package
    case_data = socket.assigns.case_data

    matching =
      if is_map(package) and is_map(case_data) do
        Enum.filter(package["evidence"], &matching_evidence?(&1, case_data))
      else
        []
      end

    evidence =
      Enum.find(matching, &(&1["id"] == socket.assigns.selected_evidence)) ||
        if(is_nil(socket.assigns.selected_evidence), do: List.first(matching))

    result =
      cond do
        is_nil(package) ->
          %{status: "unavailable", reason: "No comparison evidence"}

        not is_map(case_data) ->
          %{status: "unavailable", reason: "No valid active case"}

        is_nil(evidence) ->
          %{status: "unavailable", reason: "No evidence for this exact input and alternative"}

        true ->
          case Part3RepairPacket.build(package, evidence["id"]) do
            {:ok, _} -> %{status: "ready", id: evidence["id"]}
            {:error, reason} -> %{status: "unavailable", reason: inspect(reason)}
          end
      end

    assign(socket,
      selected_evidence:
        if(is_nil(socket.assigns.selected_evidence) and evidence,
          do: evidence["id"],
          else: socket.assigns.selected_evidence
        ),
      repair_status: result
    )
  end

  defp matching_evidence?(%{"input" => input}, case_data) when is_map(input) do
    witness = %{
      "before" => case_data["before"],
      "event" => case_data["event"],
      "output" => case_data["candidate"],
      "follow_on" => nil
    }

    Canonical.digest(input) == Canonical.digest(witness)
  end

  defp matching_evidence?(_, _), do: false

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

  defp experiment_doc(%{experiment: nil} = assigns), do: assigns.doc
  defp experiment_doc(assigns), do: assigns.experiment.doc
  defp evaluation_doc(%{preview: nil} = assigns), do: experiment_doc(assigns)

  defp evaluation_doc(assigns),
    do: Map.update!(experiment_doc(assigns), "steps", &(&1 ++ [assigns.preview]))

  defp selected(%{preview: preview}) when is_map(preview), do: preview

  defp selected(assigns),
    do: if(assigns.doc, do: Trace.step(experiment_doc(assigns), assigns.cursor))

  defp save_experiment(socket, exp) do
    case Experiment.save(socket.assigns.doc, exp) do
      {:ok, saved} ->
        {:noreply,
         socket
         |> assign(doc: saved, cursor: exp.cursor, experiment: nil, preview: nil)
         |> refresh_case(socket.assigns.candidate)
         |> load_package()}

      {:error, reason, partial, remaining} ->
        {:noreply,
         socket
         |> assign(doc: partial, experiment: remaining, preview: nil)
         |> error(
           "Saving stopped: #{reason}. #{length(remaining.pending)} steps are still unsaved. Your experiment is kept here."
         )}
    end
  end

  defp prepare_experiment(socket) do
    exp = socket.assigns.experiment || Experiment.new(socket.assigns.doc, socket.assigns.cursor)
    exp = %{exp | cursor: socket.assigns.cursor}

    case socket.assigns.preview do
      nil ->
        {:ok, exp}

      step ->
        Experiment.run(exp, %{
          "kind" => "append",
          "parent" => step["parent"],
          "event" => step["event"]
        })
    end
  end

  defp run_experiment(socket, action) do
    with {:ok, exp} <- prepare_experiment(socket),
         {:ok, updated} <- Experiment.run(exp, action.(exp)) do
      {:noreply,
       socket
       |> assign(
         experiment: updated,
         cursor: updated.cursor,
         preview: nil,
         hunt: %{status: "idle"}
       )
       |> refresh_case(nil)}
    else
      {:error, reason} -> {:noreply, error(socket, "Could not run this event: #{reason}.")}
    end
  end

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
    reading_links = Links.project(assigns.reading || %{}, assigns.case_data,
      assigns.binding_index, assigns.basis)

    active_links =
      case assigns.selection do
        %{type: :step, index: i} ->
          Enum.filter(reading_links.links, &(i in &1["steps"]))
        %{type: :clause, path: path, phase: phase, binding: binding, basis: basis,
          generation: generation} ->
          if basis == assigns.basis and generation == get_in(assigns.reading || %{}, ["source_generation"]),
            do: Enum.filter(reading_links.links, &(&1["path"] == path and &1["phase"] == phase and &1["binding"] == binding)),
            else: []
        _ -> []
      end

    assigns = assign(assigns, reading_links: reading_links, active_links: active_links)

    ~H"""
    <Layouts.app flash={@flash}>
      <p :if={!@doc} role="status">Opening ledger…</p>
      <div :if={@doc && @reading} id="review-document">
        <header class="review-bar">
          <.form for={to_form(%{"slug" => @slug})} id="law-picker" phx-change="law_change">
            <.input
              name="slug"
              value={@slug}
              type="select"
              label="Choose a rule"
              options={Enum.map(@catalog, &{ReviewCopy.title(&1), &1["slug"]})}
            />
          </.form>
        </header>
        <p :if={!Trace.current?(@doc)} role="alert" id="stale-session">
          The source files changed. Reopen this rule to run it again.
        </p>
        <.comparison
          reading={@reading} case={@case_data} step={selected(assigns)} package={@package}
          delta={@delta} preview={@preview} compare_form={@compare_form}
          snapshots={@snapshots} show_sources={@show_sources} doc={@doc}
        />
        <div class="connected-experiment">
          <section class="case-stage" aria-label="Experiment and outputs">
            <.timeline doc={experiment_doc(assigns)} cursor={@cursor} preview={@preview} saved={@doc} />
            <div class="active-case" id="active-case">
              <h2>Active case</h2>
              <.active_state doc={evaluation_doc(assigns)} cursor={@cursor} step={selected(assigns)} />
              <.input_strip case={@case_data} preview={@preview} />
              <p :if={@preview || @experiment} id="scratch-status" class="scratch-label">
                Unsaved experiment <button phx-click="reset_experiment">Reset</button>
              </p>
              <.contrast case={@case_data} step={selected(assigns)} slug={@slug} invalid={@invalid} />
            </div>
          </section>
          <section class="case-results" id="case-findings" aria-label="Active case checks">
            <.verdict case={@case_data} slug={@slug} />
            <.pair_results
              case={@case_data} reading={@reading} step={selected(assigns)}
              package={@package} preview={nil}
            />
            <section id="nearby-observation" aria-label="Observation and local repair">
              <div class="section-heading">
                <h3>Record what you noticed</h3>
                <button id="add-observation" phx-click="toggle_note" aria-expanded={to_string(@note_open)}>
                  {if @note_open, do: "Close observation", else: "Add observation"}
                </button>
              </div>
              <.form :if={@note_open} for={@note_form} id="note-form" phx-submit="record_note">
                <.input field={@note_form[:text]} type="textarea" label="Your observation" />
                <p class="scope-note">An unsaved experiment is identified in the note. This does not save pending events.</p>
                <button type="submit">Record observation</button>
              </.form>
              <details id="disposition-options" class="disposition-more">
                <summary>Review disposition options</summary>
                <.disposition package={@package} doc={@doc} selected_evidence={@selected_evidence} />
              </details>
              <p :if={@repair_status.status == "ready"} class="repair-actions" id="repair-ready">
                <a href={"/comparisons/#{@package["id"]}/repair/#{@repair_status.id}.json"}>
                  Download local repair packet (JSON)
                </a>
                <a href={"/comparisons/#{@package["id"]}/repair/#{@repair_status.id}.md"}>
                  Markdown
                </a>
              </p>
              <p :if={@repair_status.status != "ready"} id="repair-unavailable" class="scope-note">
                Repair download unavailable: {@repair_status.reason}.
                A local alternative is not matching source-comparison evidence.
              </p>
            </section>
          </section>
          <div class="case-editing">
              <section :if={@tools} id="case-tools" class="inline-tools" phx-hook="InlineTools">
                <header>
                  <h3>
                    {case @tools do
                      "draft" -> "Edit the alternative result"
                      "events" -> "Run another event"
                      _ -> "Starting account"
                    end}
                  </h3><button id="close-tools" phx-click="close_tools">Done editing</button>
                </header>
                <div :if={@tools == "draft"}>
                  <.draft_tools case={@case_data} step={selected(assigns)} preview={@preview} /><.form
                    :if={@candidate_form}
                    for={to_form(%{"amount" => @candidate_form.params["used_amount"]})}
                    id="alternative-counter"
                    phx-change="alternative_total"
                  >
                    <.input
                      name="amount"
                      value={@candidate_form.params["used_amount"]}
                      type="number"
                      label="Money reserved (¢)"
                    />
                    <p :if={@case_data} id="inline-checks">
                      Accounting: {if @case_data["candidate_valid"],
                        do: "balances",
                        else: "does not balance"} · Rule: {ReviewCopy.check(@case_data["law_status"])}
                    </p>
                  </.form><div class="candidate-search">
                    <button
                      phx-click="hunt"
                      id="hunt-candidate"
                      disabled={!@case_data || @hunt.status == "running"}
                    >Try six alternatives</button><button
                      :if={@hunt.status == "running"}
                      phx-click="cancel_hunt"
                    >Stop search</button><output id="hunt-status">{@hunt.status}{if @hunt[:cases],
                      do: " · #{@hunt.cases} cases · #{@hunt.elapsed_ms}ms · seed #{@hunt.seed}"}</output>
                  </div><.editors
                    :if={@advanced}
                    case={@case_data}
                    editor="candidate"
                    candidate_form={@candidate_form}
                    initial_form={@initial_form}
                  />
                </div>
                <.event_controls
                  :if={@tools == "events"}
                  builder_open={true}
                  doc={@doc}
                  event_form={@event_form}
                  step={selected(assigns)}
                  preview={nil}
                />
                <.editors
                  :if={@tools == "initial"}
                  case={@case_data}
                  editor="initial"
                  candidate_form={@candidate_form}
                  initial_form={@initial_form}
                />
              </section>
              <div class="experiment-actions">
                <button id="record-event" phx-click="open_tools" phx-value-tool="events">Run another event</button><button
                  id="append-preview"
                  phx-click="apply_preview"
                  disabled={!@preview && !@experiment}
                >Save experiment</button>
              </div>
          </div>
          <div class="case-reasoning">
            <section id="clauses-panel">
              <.dissector
                reading={@reading} case={@case_data} basis={@basis} helper={@helper}
                binding_index={@binding_index} links={@reading_links.links}
                unavailable={@reading_links.unavailable} active_links={@active_links}
                selection={@selection} generation={@reading["source_generation"]}
              />
            </section>
            <section id="proof-panel">
              <.proof_source
                reading={@reading} stage={@stage} full={@proof_full}
                active_links={@active_links} links={@reading_links.links}
              />
              <section :if={@inspected} id="inline-source" class="inline-source">
                <header>
                  <h3>{@inspected.name}</h3><button phx-click="close_source">Close source</button>
                </header><pre>{@inspected.bytes}</pre>
              </section>
            </section>
          </div>
        </div>
        <nav class="evidence-links" id="inspector-tools">
          <button
            :for={
              {view, label} <- [
                {"proof", "Proof"},
                {"clauses", "Conditions"},
                {"premises", "Assumptions"},
                {"artifacts", "Verification files"},
                {"record", "Review notes"}
              ]
            }
            phx-click="inspect"
            phx-value-view={view}
          >{label}</button>
        </nav>
        <section :if={@secondary == "premises"} id="premises-panel" class="secondary-panel">
          <h2>What the payment processor must guarantee</h2><.premise
            case={@case_data}
            fencing={@fencing}
            selected_key={@premise_key}
          /><.assumptions reading={@reading} show_status={false} />
        </section>
        <section :if={@secondary == "artifacts"} id="artifacts-panel" class="secondary-panel">
          <h2>Verification files</h2><.verification_files reading={@reading} /><button
            :if={@package}
            phx-click="pair_proof"
            id="pair-proof"
          >Read reports for both versions</button><.pair_artifacts
            :if={@package_proof}
            proof={@package_proof}
            package={@package}
            slug={@slug}
          />
        </section>
        <section :if={@secondary == "record"} id="record-panel" class="secondary-panel">
          <h2>Review notes</h2><section id="session-record">
            <a href={~p"/sessions/#{@doc["id"]}/export"}>Download saved session</a>
            <button phx-click="save_challenge" disabled={!@case_data || @preview != nil || @experiment != nil}>
              Save this case for review
            </button>
            <span>{length(@doc["challenges"])} saved cases</span>
          </section><.review_history package={@package} doc={@doc} />
        </section>
      </div>
    </Layouts.app>
    """
  end
end
