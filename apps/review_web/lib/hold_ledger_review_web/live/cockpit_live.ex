defmodule HoldLedgerReviewWeb.CockpitLive do
  use HoldLedgerReviewWeb, :live_view
  import HoldLedgerReviewWeb.ContrastComponents
  import HoldLedgerReviewWeb.DissectorComponents
  import HoldLedgerReviewWeb.LeanComponents
  import HoldLedgerReviewWeb.ScrubberComponents

  alias HoldLedgerReview.{
    Contrast,
    Part3ContractDelta,
    Part3ProofInspector,
    Part3Runner,
    Part3Store,
    ProofReading,
    TermCodec,
    Trace
  }

  @impl true
  def mount(_, _, socket) do
    {:ok, catalog} = ProofReading.catalog()

    {:ok,
     assign(socket,
       page_title: "Hold Ledger · Verification",
       catalog: catalog,
       slug: "po_exposure_retain",
       reading: nil,
       doc: nil,
       cursor: "start",
       case_data: nil,
       candidate: nil,
       invalid: false,
       basis: "candidate",
       helper: nil,
       stage: 0,
       reference: nil,
       editor: nil,
       candidate_form: nil,
       initial_form: nil,
       json_form: nil,
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
    slug = params["slug"] || "po_exposure_retain"

    case ProofReading.document(slug) do
      {:ok, reading} ->
        socket =
          assign(socket, slug: slug, reading: reading, stage: 0, reference: nil, helper: nil)

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
  def handle_event("law_change", %{"slug" => slug}, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/claims/#{slug}")}

  def handle_event("inspect_law", %{"slug" => slug}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/claims/#{slug}/#{socket.assigns.doc["id"]}")}

  def handle_event("basis", %{"value" => value}, socket) when value in ~w(actual candidate),
    do: {:noreply, assign(socket, basis: value, helper: nil)}

  def handle_event("helper", params, socket) do
    with phase when phase in ~w(requires actual candidate) <- params["phase"],
         {binding, ""} when binding >= 0 <- Integer.parse(params["binding"]),
         {index, ""} when index >= 0 <- Integer.parse(params["index"]),
         row when is_map(row) <-
           Enum.at(socket.assigns.case_data["explanation"]["bindings"], binding),
         tree when is_map(tree) <- row[phase],
         node when is_map(node) <- Enum.at(frontier(tree), index) do
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

  def handle_event("lemma", %{"name" => name}, socket),
    do:
      {:noreply,
       assign(socket,
         reference: Enum.find(socket.assigns.reading["references"], &(&1["name"] == name))
       )}

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
    do: {:noreply, assign(socket, editor: "candidate")}

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
    {:noreply, assign(socket, initial_form: to_form(params, as: :initial), editor: "initial")}
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

  def handle_event("previous", _, socket) do
    case selected(socket.assigns) do
      nil -> {:noreply, socket}
      step -> select_step(socket, step["parent"])
    end
  end

  def handle_event("next", _, socket) do
    case Enum.find(socket.assigns.doc["steps"], &(&1["parent"] == socket.assigns.cursor)) do
      nil -> {:noreply, socket}
      step -> select_step(socket, step["id"])
    end
  end

  def handle_event("scrub", %{"position" => position}, socket) do
    path = trace_path(socket.assigns.doc, socket.assigns.cursor)

    case Integer.parse(position) do
      {0, ""} -> select_step(socket, "start")
      {n, ""} when n > 0 and n <= length(path) -> select_step(socket, Enum.at(path, n - 1)["id"])
      _ -> {:noreply, socket}
    end
  end

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

        mutate(
          socket,
          %{"kind" => "append", "parent" => socket.assigns.cursor, "event" => json},
          true
        )

      _ ->
        {:noreply, error(socket, "Invalid event fields.")}
    end
  end

  def handle_event("next_request", _, socket) do
    {:ok, state} = Trace.state_at(socket.assigns.doc, socket.assigns.cursor)
    ledger = if socket.assigns.doc["mode"] == "ledger", do: state, else: state["ledger"]
    keys = Enum.map(ledger["entries"], & &1["key"])
    key = Enum.find(1..10, &(&1 not in keys))

    params = %{
      "type" => "request",
      "key" => to_string(key),
      "amount" => "100",
      "outcome" => "approved"
    }

    handle_event("apply_event", %{"event" => params}, socket)
  end

  def handle_event("confirm_void", _, socket) do
    params = %{
      "type" => "void_confirmed",
      "key" => first_key(socket.assigns),
      "amount" => "1",
      "outcome" => "approved"
    }

    handle_event("apply_event", %{"event" => params}, socket)
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
      {:ok, package} -> mutate(socket, %{"kind" => "comparison", "id" => package["id"]}, false)
      _ -> {:noreply, error(socket, "Compatible locally staged snapshots required.")}
    end
  end

  def handle_event("pair_proof", _, socket) do
    case Part3ProofInspector.inspect(socket.assigns.package) do
      {:ok, proof} -> {:noreply, assign(socket, package_proof: proof)}
      _ -> {:noreply, error(socket, "Matching proof artifacts unavailable.")}
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
           socket.assigns.doc,
           socket.assigns.cursor,
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
      do: {:noreply, socket |> assign(cursor: id, editor: nil) |> refresh_case(nil)},
      else: {:noreply, socket}
  end

  defp mutate(socket, action, move?) do
    doc = socket.assigns.doc

    case Trace.command(doc["id"], doc["revision"], Trace.token(), action) do
      {:ok, updated} ->
        cursor = if move?, do: command_cursor(updated, action), else: socket.assigns.cursor

        {:noreply,
         socket |> assign(doc: updated, cursor: cursor) |> refresh_case(nil) |> load_package()}

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
      if connected?(socket), do: Phoenix.PubSub.subscribe(HoldLedgerReview.PubSub, "part3:" <> id)

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

  defp selected(assigns), do: if(assigns.doc, do: Trace.step(assigns.doc, assigns.cursor))
  defp last_id(doc), do: if(doc["steps"] == [], do: "start", else: List.last(doc["steps"])["id"])
  defp trace_path(doc, cursor), do: Trace.path(doc, leaf(doc, cursor))

  defp leaf(doc, cursor) do
    case Enum.find(doc["steps"], &(&1["parent"] == cursor)) do
      nil -> cursor
      next -> leaf(doc, next["id"])
    end
  end

  defp first_key(assigns) do
    {:ok, json} = Trace.state_at(assigns.doc, assigns.cursor)

    case json["entries"] do
      [entry | _] -> to_string(entry["key"])
      _ -> "1"
    end
  end

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

  defp evidence_value(value, key) when is_map(value), do: Jason.encode!(value[key])
  defp evidence_value(value, _), do: Jason.encode!(value)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <header class="cockpit-heading">
        <h1>Hold Ledger</h1>
        <.form for={to_form(%{"slug" => @slug})} id="law-picker" phx-change="law_change">
          <.input
            name="slug"
            value={@slug}
            type="select"
            label="Law"
            options={Enum.map(@catalog, &{&1["title"], &1["slug"]})}
          />
        </.form>
      </header>
      <p :if={@doc && !Trace.current?(@doc)} role="alert" id="stale-session">
        Session source changed. Its results cannot be used as current evidence.
      </p>
      <div :if={@reading} class="instrument-grid">
        <.contrast
          case={@case_data}
          step={selected(assigns)}
          slug={@slug}
          editor={@editor}
          candidate_form={@candidate_form}
          initial_form={@initial_form}
          invalid={@invalid}
        />
        <.dissector case={@case_data} reading={@reading} basis={@basis} helper={@helper} />
        <.bridge reading={@reading} stage={@stage} reference={@reference} />
        <.assumptions reading={@reading} />
      </div>
      <.scrubber
        :if={@doc}
        doc={@doc}
        cursor={@cursor}
        event_form={@event_form}
        path={trace_path(@doc, @cursor)}
      />
      <section :if={@doc} class="surface" id="session-record">
        <div class="action-row">
          <a href={~p"/sessions/#{@doc["id"]}/export"}>Download session</a>
          <button phx-click="save_challenge" disabled={!@case_data}>Save challenge</button>
          <span>{length(@doc["challenges"])} saved challenges</span>
        </div>
        <.form for={@note_form} id="note-form" phx-submit="record_note">
          <.input field={@note_form[:text]} type="textarea" label="Review note" />
          <button>Record concern</button>
        </.form>
        <p :for={note <- @doc["notes"]}>{note["text"]}</p>
      </section>
      <details :if={@doc} class="surface" id="source-comparison" open={@package != nil}>
        <summary>Compare two locally staged source versions</summary>
        <.form for={@compare_form} id="compare-form" phx-submit="compare" class="form-row">
          <.input field={@compare_form[:baseline]} label="Baseline snapshot SHA-256" />
          <.input field={@compare_form[:proposal]} label="Proposal snapshot SHA-256" />
          <button>Attach source pair</button>
        </.form>
        <div :if={@package}>
          <p>Baseline {@package["baseline"]["snapshot_id"]}</p>
          <p>Proposal {@package["proposal"]["snapshot_id"]}</p>
          <button id="replay-pair" phx-click="replay" disabled={!@case_data}>Replay selected input and hypothetical output</button>
          <article :for={attempt <- @package["replay_attempts"]} class="attempt">
            <span>{attempt["status"]}</span>
            <button
              :if={attempt["status"] in ~w(queued running)}
              phx-click="cancel"
              phx-value-id={attempt["id"]}
            >Cancel</button>
          </article>
          <article :for={evidence <- @package["evidence"]} class="pair-evidence">
            <h3>{evidence["kind"]}</h3><p>{evidence["note"]}</p>
            <table>
              <thead>
                <tr>
                  <th>Value</th><th>Baseline</th><th>Proposal</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={key <- ~w(requires post_candidate post_actual)}>
                  <th>{key}</th><td>{evidence_value(evidence["baseline_result"], key)}</td><td>
                    {evidence_value(evidence["proposal_result"], key)}
                  </td>
                </tr>
              </tbody>
            </table>
            <a href={"/comparisons/#{@package["id"]}/repair/#{evidence["id"]}.json"}>Download local repair packet</a>
          </article>
          <article :for={change <- @package["source_changes"]} class="pair-source">
            <h3>{change["path"]}</h3>
            <a
              :for={side <- ~w(baseline proposal)}
              href={"/comparisons/#{@package["id"]}/source/#{side}/#{change["id"]}"}
              target="_blank"
              rel="noopener"
            >Read {side} source ↗</a>
          </article>
          <button id="pair-proof" phx-click="pair_proof">Inspect pair proof artifacts</button>
          <div :if={@package_proof} id="pair-proof-artifacts">
            <section :for={version <- @package_proof["versions"]}>
              <h3>{version["side"]}</h3><p>{version["formal_acceptance"]}</p>
              <p>{version["report_status"]} · {version["catalog_count"]} catalog obligations</p>
              <article :for={law <- Enum.filter(version["sources"], &(&1["slug"] == @slug))}>
                <p>{law["slug"]}: {law["artifact_scope"]}</p>
                <p>
                  Translation: {if law["translated_statement"], do: "supplied", else: "missing"} · Dependencies: {if law[
                                                                                                                       "proof_dependencies"
                                                                                                                     ],
                                                                                                                     do:
                                                                                                                       "supplied",
                                                                                                                     else:
                                                                                                                       "missing"}
                </p>
                <pre :if={law["translated_statement"]}>{Jason.encode!(law["translated_statement"], pretty: true)}</pre>
                <pre :if={law["proof_dependencies"]}>{Jason.encode!(law["proof_dependencies"], pretty: true)}</pre>
                <pre :if={law["exports"] != []}>{Jason.encode!(law["exports"], pretty: true)}</pre>
              </article>
              <ul>
                <li :for={item <- version["artifacts"]}>
                  <a
                    :if={item["status"] == "present"}
                    href={"/comparisons/#{@package["id"]}/artifact/#{version["side"]}/#{item["sha256"]}"}
                    target="_blank"
                    rel="noopener"
                  >{item["kind"]} · {item["path"]} ↗</a>
                  <span :if={item["status"] != "present"}>{item["path"]}: {item["status"]}</span>
                </li>
              </ul>
            </section>
          </div>
        </div>
      </details>
    </Layouts.app>
    """
  end
end
