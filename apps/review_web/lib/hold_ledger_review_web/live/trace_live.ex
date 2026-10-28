defmodule HoldLedgerReviewWeb.TraceLive do
  use HoldLedgerReviewWeb, :live_view

  alias HoldLedgerReview.{
    Part3ContractDelta,
    Part3ProofInspector,
    Part3Runner,
    Part3Store,
    TermCodec,
    Trace
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Hold Ledger Explorer",
       doc: nil,
       cursor: "start",
       topic: "admission",
       detail: nil,
       candidate: nil,
       starting: nil,
       candidate_result: nil,
       package: nil,
       delta: %{},
       proof: nil,
       formal: nil,
       form: to_form(%{"amount" => "100", "slots" => "2", "mode" => "ledger"}, as: :start),
       event_form: event_form(),
       compare_form: to_form(%{}, as: :compare),
       note_form: to_form(%{"disposition" => "concern"}, as: :note)
     )}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Trace.get(id) do
      {:ok, doc} ->
        last = List.last(doc["steps"])

        {:noreply,
         socket
         |> assign(
           doc: doc,
           cursor: if(last, do: last["id"], else: "start"),
           formal: trace_formal(doc)
         )
         |> load_package()}

      _ ->
        {:noreply, put_flash(socket, :error, "This trace is unavailable.")}
    end
  end

  def handle_params(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_event("create", %{"start" => params}, socket) do
    with {amount, ""} <- Integer.parse(params["amount"]),
         {slots, ""} <- Integer.parse(params["slots"]),
         {:ok, doc} <- Trace.create(params["mode"], amount, slots) do
      {:noreply, push_navigate(socket, to: ~p"/explore/#{doc["id"]}")}
    else
      _ ->
        {:noreply,
         put_flash(socket, :error, "Use whole cents and slots between 0 and 1,000,000.")}
    end
  end

  def handle_event("edit_start", _, socket) do
    json = state_json(socket.assigns)

    params =
      Map.update!(json, "entries", fn entries ->
        entries |> Enum.with_index() |> Map.new(fn {entry, i} -> {to_string(i), entry} end)
      end)

    {:noreply, assign(socket, starting: to_form(params, as: :state))}
  end

  def handle_event("initial_change", %{"state" => params}, socket),
    do: {:noreply, assign(socket, starting: to_form(params, as: :state))}

  def handle_event("add_initial_entry", _, socket) do
    params = socket.assigns.starting.params
    entries = params["entries"] || %{}

    if map_size(entries) < 8 do
      next = to_string(map_size(entries))
      entries = Map.put(entries, next, %{"key" => next, "amount" => "1", "status" => "reserved"})

      {:noreply,
       assign(socket, starting: to_form(Map.put(params, "entries", entries), as: :state))}
    else
      {:noreply, put_flash(socket, :error, "At most eight entries can be explored.")}
    end
  end

  def handle_event("remove_initial_entry", %{"index" => index}, socket) do
    params = socket.assigns.starting.params

    entries =
      (params["entries"] || %{})
      |> Map.delete(index)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.with_index()
      |> Map.new(fn {{_, entry}, i} -> {to_string(i), entry} end)

    {:noreply, assign(socket, starting: to_form(Map.put(params, "entries", entries), as: :state))}
  end

  def handle_event("save_initial", %{"state" => params}, socket) do
    with {:ok, json} <- initial_json(params), {:ok, doc} <- Trace.create_from(json) do
      {:noreply, push_navigate(socket, to: ~p"/explore/#{doc["id"]}")}
    else
      _ ->
        {:noreply,
         socket
         |> assign(starting: to_form(params, as: :state))
         |> put_flash(
           :error,
           "Starting counters must match unique entries and fit both limits. Nothing was saved."
         )}
    end
  end

  def handle_event("recalculate_initial", _, socket) do
    with {:ok, json} <- initial_json(socket.assigns.starting.params),
         {:ok, state} <- TermCodec.decode_state(json) do
      params = socket.assigns.starting.params

      params =
        params
        |> Map.put("used_amount", HoldLedger.Spec.hold_amount(elem(state, 4)))
        |> Map.put("used_holds", HoldLedger.Spec.hold_count(elem(state, 4)))

      {:noreply, assign(socket, starting: to_form(params, as: :state))}
    else
      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Use bounded whole numbers and known statuses before recalculating."
         )}
    end
  end

  def handle_event("previous", _, socket) do
    case selected(socket.assigns) do
      nil -> {:noreply, socket}
      step -> select(socket, step["parent"])
    end
  end

  def handle_event("next", _, socket) do
    case Enum.find(socket.assigns.doc["steps"], &(&1["parent"] == socket.assigns.cursor)) do
      nil -> {:noreply, socket}
      step -> select(socket, step["id"])
    end
  end

  def handle_event("topic", %{"topic" => id}, socket),
    do: {:noreply, assign(socket, topic: elem(Trace.topic(id), 0))}

  def handle_event("select", %{"id" => id}, socket), do: select(socket, id)

  def handle_event("scrub", %{"position" => index}, socket) do
    path = Trace.path(socket.assigns.doc, active_leaf(socket.assigns.doc, socket.assigns.cursor))

    case Integer.parse(index) do
      {n, ""} when n >= 0 and n <= length(path) ->
        id = if n == 0, do: "start", else: Enum.at(path, n - 1)["id"]
        select(socket, id)

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("event_change", %{"event" => params}, socket) do
    {:noreply,
     assign(socket,
       event_form: to_form(Map.merge(socket.assigns.event_form.params, params), as: :event)
     )}
  end

  def handle_event("apply", %{"event" => params}, socket) do
    socket = assign(socket, event_form: to_form(params, as: :event))

    case event_json(socket.assigns.doc["mode"], params) do
      {:ok, json} ->
        mutate(
          socket,
          %{"kind" => "append", "parent" => socket.assigns.cursor, "event" => json},
          true
        )

      _ ->
        {:noreply,
         put_flash(socket, :error, "Choose an event and use bounded whole-number fields.")}
    end
  end

  def handle_event("source", %{"path" => path}, socket) do
    case Trace.source(path) do
      {:ok, bytes, digest} ->
        {:noreply, assign(socket, detail: %{title: path, body: bytes, digest: digest})}

      _ ->
        {:noreply,
         put_flash(socket, :error, "Source is missing or changed. Rebuild and start a new trace.")}
    end
  end

  def handle_event("close_detail", _, socket), do: {:noreply, assign(socket, detail: nil)}

  def handle_event("candidate", _, socket) do
    case selected(socket.assigns) do
      %{"output" => output} when is_map(output) ->
        {:noreply,
         assign(socket,
           candidate: to_form(%{"json" => Jason.encode!(output, pretty: true)}, as: :candidate),
           candidate_result: nil
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Select a ledger transition first.")}
    end
  end

  def handle_event("check_candidate", %{"candidate" => %{"json" => text}}, socket) do
    socket = assign(socket, candidate: to_form(%{"json" => text}, as: :candidate))

    with true <- byte_size(text) <= 24_000,
         {:ok, json} <- Jason.decode(text),
         {:ok, result} <- Trace.candidate(socket.assigns.doc, socket.assigns.cursor, json) do
      {:noreply, assign(socket, candidate_result: result)}
    else
      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Candidate must match the typed output format. Totals are not corrected automatically."
         )}
    end
  end

  def handle_event("recalculate", _, socket) do
    with candidate when not is_nil(candidate) <- socket.assigns.candidate,
         {:ok, json} <- Jason.decode(candidate[:json].value),
         {:ok, {state, result, effects}} <- TermCodec.decode_output(json) do
      {al, hl, _, _, entries} = state

      holding =
        Enum.filter(entries, fn {_, _, status} ->
          status in [:reserved, :sent, :unknown, :authorized, :voiding]
        end)

      state = {al, hl, Enum.sum(Enum.map(holding, &elem(&1, 1))), length(holding), entries}

      with {:ok, output} <- TermCodec.encode_output({state, result, effects}) do
        {:noreply,
         assign(socket,
           candidate: to_form(%{"json" => Jason.encode!(output, pretty: true)}, as: :candidate),
           candidate_result: nil
         )}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Check the candidate's fields first.")}
    end
  end

  def handle_event("branch_candidate", _, socket) do
    case socket.assigns.candidate_result do
      %{"valid_after" => true, "output" => output} ->
        mutate(
          socket,
          %{"kind" => "candidate", "parent" => socket.assigns.cursor, "output" => output},
          true
        )

      _ ->
        {:noreply,
         put_flash(socket, :error, "Check a valid candidate before continuing from it.")}
    end
  end

  def handle_event("note", %{"note" => params}, socket) do
    mutate(
      socket,
      %{
        "kind" => "note",
        "step" => socket.assigns.cursor,
        "text" => params["text"],
        "disposition" => params["disposition"]
      },
      false
    )
  end

  def handle_event("compare", %{"compare" => params}, socket) do
    case Part3Store.create(params["baseline"], params["proposal"]) do
      {:ok, package} ->
        mutate(socket, %{"kind" => "comparison", "id" => package["id"]}, false)

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Select compatible, trusted snapshots staged locally with the snapshot script."
         )}
    end
  end

  def handle_event("replay", _, socket) do
    with package when is_map(package) <- socket.assigns.package,
         {:ok, witness} <- witness(socket.assigns),
         {:ok, _} <- Part3Runner.replay(package["id"], witness) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "Isolated replay started. Results appear when both processes complete."
       )
       |> load_package()}
    else
      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Select a ledger transition and a compatible source pair before replay."
         )}
    end
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    _ = Part3Runner.cancel(socket.assigns.package["id"], id)
    {:noreply, load_package(socket)}
  end

  def handle_event("proof", _, socket) do
    result =
      if socket.assigns.package,
        do: Part3ProofInspector.inspect(socket.assigns.package),
        else: {:ok, socket.assigns.formal}

    case result do
      {:ok, proof} ->
        {:noreply, assign(socket, proof: proof)}

      _ ->
        {:noreply,
         put_flash(socket, :error, "Proof artifacts are unavailable for these sources.")}
    end
  end

  # No provider action is exposed by this interface. Forged events never dispatch.
  def handle_event(_, _, socket), do: {:noreply, put_flash(socket, :error, "Unknown action.")}

  @impl true
  def handle_info({:part3_updated, _id}, socket), do: {:noreply, load_package(socket)}

  defp select(socket, id) do
    if id == "start" or Trace.step(socket.assigns.doc, id),
      do: {:noreply, assign(socket, cursor: id, candidate: nil, candidate_result: nil)},
      else: {:noreply, socket}
  end

  defp mutate(socket, action, move?) do
    doc = socket.assigns.doc

    case Trace.command(doc["id"], doc["revision"], Trace.token(), action) do
      {:ok, updated} ->
        cursor = if move?, do: command_cursor(updated, action), else: socket.assigns.cursor

        {:noreply,
         socket
         |> assign(doc: updated, cursor: cursor, candidate: nil, candidate_result: nil)
         |> load_package()}

      {:error, :revision_conflict} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Another tab changed this trace. Reload before saving; your action was not applied."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Action refused: #{reason}")}
    end
  end

  defp command_cursor(doc, %{"kind" => "append", "parent" => parent, "event" => event}) do
    Enum.find(
      doc["steps"],
      &(&1["parent"] == parent and &1["event"] == event and not Map.has_key?(&1, "challenge_of"))
    )["id"]
  end

  defp command_cursor(doc, %{"kind" => "candidate", "parent" => parent, "output" => output}) do
    Enum.find(doc["steps"], &(&1["challenge_of"] == parent and &1["output"] == output))["id"]
  end

  defp load_package(socket) do
    case socket.assigns.doc["comparison"] do
      nil ->
        socket

      id ->
        if connected?(socket),
          do: Phoenix.PubSub.subscribe(HoldLedgerReview.PubSub, "part3:" <> id)

        case Part3Store.get(id) do
          {:ok, package, :ok} ->
            delta = source_delta(socket.assigns, package)

            assign(socket, package: package, delta: delta)

          _ ->
            assign(socket, package: nil)
            |> put_flash(
              :error,
              "Comparison sources changed; previous evidence remains archived."
            )
        end
    end
  end

  defp source_delta(%{package: %{"id" => id}, delta: delta}, %{"id" => id}), do: delta

  defp source_delta(_assigns, package) do
    case Part3ContractDelta.presentation(package) do
      {:ok, view} -> view
      _ -> %{}
    end
  end

  defp witness(assigns) do
    case selected(assigns) do
      %{"output" => output} = step when is_map(output) ->
        candidate =
          if assigns.candidate_result, do: assigns.candidate_result["output"], else: output

        {:ok,
         %{
           "before" => step["before"],
           "event" => step["event"],
           "output" => candidate,
           "follow_on" => nil
         }}

      _ ->
        {:error, :no_ledger_step}
    end
  end

  defp selected(assigns), do: if(assigns.doc, do: Trace.step(assigns.doc, assigns.cursor))

  defp active_leaf(doc, "start"),
    do: if(doc["steps"] == [], do: "start", else: List.last(doc["steps"])["id"])

  defp active_leaf(doc, cursor) do
    case Enum.find(doc["steps"], &(&1["parent"] == cursor)) do
      nil -> cursor
      child -> active_leaf(doc, child["id"])
    end
  end

  defp initial_json(params) do
    fields =
      Map.new(~w(amount_limit hold_limit used_amount used_holds), fn field ->
        {field, String.to_integer(to_string(params[field]))}
      end)

    entries =
      (params["entries"] || %{})
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {_, entry} ->
        %{
          "key" => String.to_integer(to_string(entry["key"])),
          "amount" => String.to_integer(to_string(entry["amount"])),
          "status" => entry["status"]
        }
      end)

    json = Map.put(fields, "entries", entries)
    with {:ok, _} <- TermCodec.decode_state(json), do: {:ok, json}
  rescue
    _ -> {:error, :invalid_starting_state}
  end

  defp entry_form(entry, index), do: to_form(entry, as: "state[entries][#{index}]")

  defp event_form,
    do:
      to_form(%{"type" => "request", "key" => "11", "amount" => "100", "outcome" => "approved"},
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

  defp state_json(assigns) do
    {:ok, state} = Trace.state_at(assigns.doc, assigns.cursor)
    if assigns.doc["mode"] == "ledger", do: state, else: state["ledger"]
  end

  defp trace_formal(doc) do
    if Trace.current?(doc),
      do: Trace.formal(),
      else: %{
        status: :stale,
        detail:
          "This trace belongs to different source. Current reports do not certify its receipts.",
        report: nil
      }
  end

  defp catalog do
    case HoldLedgerReview.Claims.catalog() do
      {:ok, catalog} -> catalog
      _ -> []
    end
  end

  defp exposure_json(assigns), do: elem(Trace.state_at(assigns.doc, assigns.cursor), 1)

  defp selected_claim_status(step, topic) do
    case Enum.find(step["checks"], &(&1["slug"] == topic_law(topic))) do
      nil -> "This law is not probed for the selected operation."
      row -> check_label(row["status"])
    end
  end

  defp effect_text(%{"type" => "authorize", "key" => key, "amount" => amount}),
    do: "Request authorization: key #{key}, #{amount}¢"

  defp effect_text(%{"type" => "void", "key" => key}), do: "Request remote void: key #{key}"

  defp pretty(value), do: Jason.encode!(value, pretty: true)
  defp topic_law(id), do: elem(Trace.topic(id), 3)
  defp formal_status(nil), do: "not loaded"
  defp formal_status(%{status: :not_supplied}), do: "No report supplied"
  defp formal_status(formal), do: to_string(formal.status)

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :step, selected(assigns))

    ~H"""
    <Layouts.app flash={@flash}>
      <section class="explorer-heading">
        <div>
          <p class="eyebrow">Source → claim → consequence</p><h1>Explore a guarantee.</h1>
        </div>
        <a :if={@doc} href={~p"/"} class="button">New trace</a>
      </section>
      <section :if={!@doc} class="start-panel">
        <h2>Start with an account</h2>
        <p>
          Choose limits, apply an event, then step through what changes. Amounts are integer cents.
        </p>
        <.form for={@form} id="start-trace" phx-submit="create" class="controls">
          <.input
            field={@form[:amount]}
            type="number"
            label="Amount limit (¢)"
            min="0"
            max="1000000"
            required
          />
          <.input
            field={@form[:slots]}
            type="number"
            label="Hold slots"
            min="0"
            max="1000000"
            required
          />
          <.input
            field={@form[:mode]}
            type="select"
            label="Explore"
            options={[{"Local ledger", "ledger"}, {"Ledger + modeled processor", "exposure"}]}
          />
          <button class="primary" id="create-trace">Start exploring</button>
        </.form>
        <p class="muted">
          No payment processor or model is contacted. The coupled model lets you deliver remote events separately.
        </p>
      </section>
      <section :if={@doc} id="explorer" aria-label="Guarantee explorer">
        <div class="trace-toolbar">
          <form phx-change="topic" id="topic-form">
            <label for="topic">Guarantee</label>
            <select name="topic" id="topic"><option
              :for={{id, title, _, _} <- Trace.topics()}
              value={id}
              selected={id == @topic}
            >
              {title}
            </option></select>
          </form>
          <span id="trace-mode">{if @doc["mode"] == "ledger",
            do: "Local ledger",
            else: "Coupled processor model"}</span>
          <span :if={!Trace.current?(@doc)} role="alert" class="alarm">Source changed · read only</span>
          <a href={~p"/explore/#{@doc["id"]}/export"}>Export trace</a>
        </div>
        <div class="anchor-grid">
          <section class="anchor" id="guarantee-panel">
            <p class="eyebrow">01 / Guarantee</p><h2>{elem(Trace.topic(@topic), 1)}</h2>
            <p>{elem(Trace.topic(@topic), 2)}</p>
            <button phx-click="source" phx-value-path="guides/specification.md" class="text-button">Read governing policy
            <.icon name="hero-arrow-up-right" class="size-4" /></button>
          </section>
          <section class="anchor" id="source-panel">
            <p class="eyebrow">02 / Source & change</p><h2>Follow the claim</h2>
            <p :if={@step} id="selected-claim-status">{selected_claim_status(@step, @topic)}</p>
            <p>
              <code>{topic_law(@topic)}</code> is an entry point for this guarantee.
            </p>
            <button phx-click="source" phx-value-path="lib/hold_ledger/spec.ex" class="text-button">Conditions and independent reference</button>
            <button phx-click="source" phx-value-path="lib/hold_ledger/ledger.ex" class="text-button">Implementation transitions</button>
            <button
              :for={path <- Enum.filter(Trace.sources(), &String.contains?(&1, topic_law(@topic)))}
              phx-click="source"
              phx-value-path={path}
              class="text-button"
            >Law and proof source</button>
          </section>
          <section class="anchor" id="result-panel">
            <p class="eyebrow">03 / Concrete result</p><h2>
              {if @step, do: event_label(@step["event"]), else: "Choose the first event"}
            </h2>
            <div :if={@step}>
              <p :if={@step["origin"] != "computed"} class="alarm" id="hypothetical-label">
                Hypothetical branch · not observed implementation behavior
              </p>
              <dl :if={@step["output"]}>
                <dt>Result</dt><dd id="actual-result">{@step["output"]["result"]}</dd><dt>
                  Independent reference
                </dt><dd>{@step["oracle"]["result"]}</dd><dt>Requested effects</dt><dd>
                  <span :if={@step["output"]["effects"] == []}>None</span><span :for={
                    effect <- @step["output"]["effects"]
                  }>{effect_text(effect)}</span>
                </dd>
              </dl>
              <p :if={!@step["output"]}>
                {if @step["before"] == @step["after"],
                  do: "No modeled state change.",
                  else: "Modeled state changed."} Remote delivery and local observation are separate events.
              </p>
              <button
                :if={@step["output"]}
                phx-click="candidate"
                id="edit-candidate"
                class="text-button"
              >Try a different outcome</button>
            </div>
            <p :if={!@step}>
              The implementation computes a result. A law separately checks what it promises about that result.
            </p>
          </section>
          <section class="anchor" id="evidence-panel">
            <p class="eyebrow">04 / Assumptions & evidence</p><h2>Know the boundary</h2>
            <p id="formal-status">Formal report: {formal_status(@formal)}</p>
            <p :if={@topic == "exposure" || @doc["mode"] == "exposure"}>
              The model assumes truthful processor outcomes, identity retention and permanent terminal fencing. Real processor support is unestablished here.
            </p>
            <p :if={@topic == "recovery"}>
              Pure replay does not establish physical journal durability. Runtime and storage evidence remain separate.
            </p>
            <p :if={@topic not in ~w(exposure recovery) && @doc["mode"] == "ledger"}>
              Valid starting states and bounded concrete inputs. These executions do not establish the law universally.
            </p>
            <button phx-click="proof" id="inspect-proof" class="text-button">Inspect available proof evidence</button>
            <button
              :if={@doc["mode"] == "exposure"}
              phx-click="source"
              phx-value-path="lib/hold_ledger/environment.ex"
              class="text-button"
            >Inspect processor assumptions</button>
          </section>
        </div>
        <section :if={@starting} class="surface" id="starting-editor">
          <h2>Adjust the starting state</h2><p>
            Saving starts a new trace. Existing branches remain intact. Counters change only when you edit or recalculate them.
          </p>
          <.form
            for={@starting}
            id="starting-form"
            phx-change="initial_change"
            phx-submit="save_initial"
          >
            <div class="controls">
              <.input
                :for={field <- ~w(amount_limit hold_limit used_amount used_holds)}
                field={@starting[field]}
                type="number"
                label={String.replace(field, "_", " ")}
                min="0"
                max="1000000"
              />
            </div>
            <div :for={{index, entry} <- @starting.params["entries"] || %{}} class="controls">
              <.input field={entry_form(entry, index)[:key]} type="number" label="Key" />
              <.input field={entry_form(entry, index)[:amount]} type="number" label="Amount (¢)" />
              <button type="button" phx-click="remove_initial_entry" phx-value-index={index}>Remove entry</button>
              <.input
                field={entry_form(entry, index)[:status]}
                type="select"
                label="Status"
                options={TermCodec.statuses()}
              />
            </div>
            <button id="save-starting" class="primary">Start a new trace from this state</button>
          </.form>
          <button phx-click="add_initial_entry" id="add-entry">Add entry</button>
          <button phx-click="recalculate_initial" id="recalculate-initial">Recalculate used totals</button>
        </section>
        <section class="machine" id="state-machine">
          <div class="section-heading">
            <h2>Account at this step</h2><span class="eyebrow" id="trace-revision">Revision {@doc[
              "revision"
            ]}</span>
          </div>
          <p :if={@step} id="transition-summary">{transition_summary(@step, @doc["mode"])}</p>
          <div class="capacity-grid">
            <div>
              <span>Reserved / amount limit</span><strong id="amount-counter">{state_json(assigns)[
                "used_amount"
              ]}¢ / {state_json(assigns)["amount_limit"]}¢</strong><meter
                min="0"
                max={max(1, state_json(assigns)["amount_limit"])}
                value={state_json(assigns)["used_amount"]}
              >Amount reserved</meter>
            </div>
            <div>
              <span>Used / hold slots</span><strong id="slot-counter">{state_json(assigns)[
                "used_holds"
              ]} / {state_json(assigns)["hold_limit"]}</strong><meter
                min="0"
                max={max(1, state_json(assigns)["hold_limit"])}
                value={state_json(assigns)["used_holds"]}
              >Slots used</meter>
            </div>
            <div>
              <span>Available amount</span><strong>{state_json(assigns)["amount_limit"] -
                state_json(assigns)["used_amount"]}¢</strong>
            </div>
          </div>
          <table id="entries">
            <caption>Remembered identities</caption><thead>
              <tr>
                <th>Key</th><th>Amount</th><th>Status</th>
              </tr>
            </thead><tbody>
              <tr :for={entry <- state_json(assigns)["entries"]}>
                <td>{entry["key"]}</td><td>{entry["amount"]}¢</td><td>{entry["status"]}</td>
              </tr>
              <tr :if={state_json(assigns)["entries"] == []}>
                <td colspan="3">No entries yet.</td>
              </tr>
            </tbody>
          </table>
          <div :if={@doc["mode"] == "exposure"} id="remote-state" class="remote-state">
            <h3>Modeled processor · distinct from local observations</h3><table>
              <caption>Remote records</caption><thead>
                <tr>
                  <th>Key</th><th>Amount</th><th>Status</th>
                </tr>
              </thead><tbody>
                <tr :for={entry <- exposure_json(assigns)["remote"]}>
                  <td>{entry["key"]}</td><td>{entry["amount"]}¢</td><td>{entry["status"]}</td>
                </tr>
              </tbody>
            </table><p>Pending void obligations: {length(exposure_json(assigns)["obligations"])}</p>
          </div>
          <button :if={@doc["mode"] == "ledger"} phx-click="edit_start" id="edit-start">Adjust starting state</button>
          <nav id="timeline" aria-label="Execution timeline">
            <button
              phx-click="select"
              phx-value-id="start"
              aria-current={if @cursor == "start", do: "step", else: "false"}
            >Start</button>
            <button
              :for={step <- @doc["steps"]}
              phx-click="select"
              phx-value-id={step["id"]}
              aria-current={if @cursor == step["id"], do: "step", else: "false"}
              title={"Parent: " <> step["parent"]}
            >{event_label(step["event"])}{if step["origin"] != "computed", do: " · hypothetical"}</button>
          </nav>
          <div class="step-controls">
            <button phx-click="previous" id="previous-step" disabled={@cursor == "start"}>Previous</button><button
              phx-click="next"
              id="next-step"
            >Next</button>
          </div>
          <form phx-change="scrub" id="scrubber">
            <label for="position">Step through this branch</label><input
              type="range"
              id="position"
              name="position"
              min="0"
              max={length(Trace.path(@doc, active_leaf(@doc, @cursor)))}
              value={length(Trace.path(@doc, @cursor))}
            />
          </form>
          <p class="muted">
            Select an earlier step and apply an event to start a branch. Previous steps stay intact.
          </p>
          <.form
            for={@event_form}
            id="next-event"
            phx-change="event_change"
            phx-submit="apply"
            class="controls"
          >
            <.input
              field={@event_form[:type]}
              type="select"
              label="Next event"
              options={event_options(@doc["mode"])}
            />
            <.input
              field={@event_form[:key]}
              type={if @event_form[:type].value == "restart", do: "hidden", else: "number"}
              label="Identity"
              min="0"
              max="1000000"
            />
            <.input
              field={@event_form[:amount]}
              type={if @event_form[:type].value == "request", do: "number", else: "hidden"}
              label="Request amount (¢)"
              min="1"
              max="1000000"
            />
            <.input
              field={@event_form[:outcome]}
              type={
                if @event_form[:type].value in ~w(processor_result authorize),
                  do: "select",
                  else: "hidden"
              }
              label="Processor outcome"
              options={~w(approved declined)}
            />
            <button id="apply-event" class="primary" disabled={!Trace.current?(@doc)}>Apply event</button>
          </.form>
        </section>
        <section :if={@step && @step["checks"] != []} id="claim-checks" class="surface">
          <h2>Claims checked on this transition</h2><p>
            Candidate acceptance here is a concrete result, not universal proof.
          </p>
          <table>
            <thead>
              <tr>
                <th>Law</th><th>Concrete result</th><th>Bindings</th>
              </tr>
            </thead><tbody>
              <tr :for={row <- @step["checks"]}>
                <td>{row["slug"]}</td><td>{check_label(row["status"])}</td><td>{row["bindings"]}</td>
              </tr>
            </tbody>
          </table>
        </section>
        <section :if={@candidate} id="candidate-panel" class="surface">
          <h2>Challenge the promise</h2><p>
            Edit the hypothetical output. Totals remain as entered until you explicitly recalculate.
          </p>
          <.form for={@candidate} id="candidate-form" phx-submit="check_candidate">
            <.input field={@candidate[:json]} type="textarea" label="Hypothetical output JSON" /><button class="primary">Check candidate</button>
          </.form>
          <button phx-click="recalculate" id="recalculate">Recalculate used totals</button>
          <div :if={@candidate_result} id="candidate-checks">
            <p>Valid resulting state: {to_string(@candidate_result["valid_after"])}</p><ul>
              <li :for={row <- @candidate_result["checks"]}>
                {row["slug"]}: {check_label(row["status"])}
              </li>
            </ul><button
              phx-click="branch_candidate"
              id="branch-candidate"
              disabled={!@candidate_result["valid_after"]}
            >Continue from this hypothetical state</button>
          </div>
        </section>
        <section class="surface" id="comparison">
          <h2>Compare source versions</h2><p>
            Optional. Stage operator-trusted worktrees locally; the browser never builds uploaded code or fetches dependencies.
          </p>
          <.form for={@compare_form} id="comparison-form" phx-submit="compare" class="controls">
            <.input field={@compare_form[:baseline]} label="Staged baseline ID" /><.input
              field={@compare_form[:proposal]}
              label="Staged proposal ID"
            /><button>Attach source pair</button>
          </.form>
          <div :if={@package} id="comparison-results">
            <p>Package <code>{@package["id"]}</code></p><button phx-click="replay" id="replay">Replay selected transition in isolated processes</button>
            <section id="source-changes">
              <h3>Changed sources</h3><p>
                Expression differences are structural evidence. Behavioral meaning requires the concrete checks or further review.
              </p>
              <article :for={change <- @package["source_changes"]}>
                <h3>{change["path"]}</h3><p>{change["kind"]} · relation unresolved</p>
                <div :for={expr <- get_in(@delta, [change["id"], "expressions"]) || []}>
                  <p>Normalized {expr["label"]}</p><div class="anchor-grid">
                    <div class="anchor">
                      <strong>Baseline</strong><pre><%= for chunk <- expr["baseline"] do %><del :if={chunk["kind"] == "del"}>{chunk["text"]}</del><span :if={chunk["kind"] == "eq"}>{chunk["text"]}</span><% end %></pre>
                    </div>
                    <div class="anchor">
                      <strong>Proposal</strong><pre><%= for chunk <- expr["proposal"] do %><ins :if={chunk["kind"] == "ins"}>{chunk["text"]}</ins><span :if={chunk["kind"] == "eq"}>{chunk["text"]}</span><% end %></pre>
                    </div>
                  </div>
                </div>
                <div class="controls">
                  <a
                    :if={change["baseline_sha256"]}
                    href={~p"/changes/#{@package["id"]}/source/baseline/#{change["id"]}"}
                  >Read baseline source</a><a
                    :if={change["proposal_sha256"]}
                    href={~p"/changes/#{@package["id"]}/source/proposal/#{change["id"]}"}
                  >Read proposal source</a>
                </div>
                <p :for={span <- get_in(@delta, [change["id"], "declarations"]) || []}>
                  {span["side"]}: declaration lines {span["start_line"]}–{span["end_line"]}
                </p>
              </article>
            </section>
            <div :for={attempt <- @package["replay_attempts"]} class="attempt">
              <span>{if attempt["snapshot_id"] == @package["baseline"]["snapshot_id"],
                do: "Baseline",
                else: "Proposal"} · {attempt["snapshot_id"] |> String.slice(0, 10)} · {attempt[
                "status"
              ]}</span><button
                :if={attempt["status"] in ~w(queued running)}
                phx-click="cancel"
                phx-value-id={attempt["id"]}
              >Cancel</button>
            </div>
            <div :for={evidence <- @package["evidence"]} class="comparison-evidence">
              <pre>{pretty(evidence)}</pre>
            </div>
            <a
              :for={evidence <- @package["evidence"]}
              href={~p"/changes/#{@package["id"]}/repair/#{evidence["id"] <> ".json"}"}
            >Download repair packet for {evidence["id"]}</a>
          </div>
        </section>
        <section class="surface" id="review-notes">
          <h2>Record a concern or scoped judgment</h2><p>
            This records human reasoning. It does not confer policy authority or formal acceptance.
          </p>
          <.form for={@note_form} id="note-form" phx-submit="note" class="controls">
            <.input
              field={@note_form[:disposition]}
              type="select"
              label="Disposition"
              options={[
                {"Concern", "concern"},
                {"Considered in scope", "considered"},
                {"Need evidence", "needs_evidence"}
              ]}
            /><.input
              field={@note_form[:text]}
              type="textarea"
              label="Reason and relevant policy or evidence"
            /><button>Record</button>
          </.form>
          <article :for={note <- @doc["notes"]}>
            <strong>{note["disposition"]}</strong><p>{note["text"]}</p>
          </article>
        </section>
        <section :if={@proof} id="proof-detail" class="surface">
          <h2>Available proof evidence</h2><p>
            The original ProofEvidence boundary alone determines formal acceptance. A source declaration is not a proof receipt.
          </p>
          <div :if={Map.has_key?(@proof, "versions")}>
            <article :for={version <- @proof["versions"]}>
              <h3>{version["side"]}: {version["formal_acceptance"]}</h3><p>
                Report: {version["report_status"]}
              </p>
              <p>Snapshot <code>{version["snapshot_id"]}</code></p>
              <table>
                <thead>
                  <tr>
                    <th>Obligation</th><th>Translation / dependencies</th><th>Export evidence</th>
                  </tr>
                </thead><tbody>
                  <tr :for={law <- version["sources"]}>
                    <td>{law["slug"]}<br />{law["purpose"]}</td><td>
                      {if law["translated_statement"],
                        do: "Statement recorded",
                        else: "Statement missing"}<br />{if law["proof_dependencies"],
                        do: "Dependencies recorded",
                        else: "Dependencies missing"}
                    </td><td>
                      {if law["exports"] == [], do: "Missing", else: "Recorded; inspect scope below"}
                    </td>
                  </tr>
                </tbody>
              </table>
              <ul>
                <li :for={artifact <- version["artifacts"]}>
                  {artifact["kind"]} · {artifact["slug"]} · {artifact["status"]}
                  <a
                    :if={artifact["status"] == "present"}
                    href={
                      ~p"/changes/#{@package["id"]}/artifact/#{version["side"]}/#{artifact["sha256"]}"
                    }
                  >Read artifact</a>
                </li>
              </ul>
              <details>
                <summary>Recorded exports, axiom scope and six checker configurations</summary><pre>{pretty(version["sources"])}</pre>
              </details>
            </article>
          </div>
          <div :if={!Map.has_key?(@proof, "versions")}>
            <p>Original report status: {formal_status(@proof)}</p><p>{@proof.detail}</p>
            <p>
              Native Lean obligations remain in the inventory. They are not converted into invented executable claims.
            </p>
            <ul>
              <li :for={law <- catalog()}>{law["slug"]} · {law["kind"]} · {law["purpose"]}</li>
            </ul>
          </div>
        </section>
        <details class="identity surface">
          <summary>Exact source and evaluator identity</summary><pre>{pretty(@doc["identity"])}</pre><p>
            Trace <code>{@doc["id"]}</code>
          </p>
        </details>
      </section>
      <section
        :if={@detail}
        class="source-detail surface"
        id="source-detail"
        aria-label="Source detail"
      >
        <div class="section-heading">
          <h2>{@detail.title}</h2><button phx-click="close_detail">Close</button>
        </div><p><code>{@detail.digest}</code></p><pre tabindex="0">{@detail.body}</pre>
      </section>
    </Layouts.app>
    """
  end

  defp transition_summary(step, mode) do
    before = if mode == "ledger", do: step["before"], else: step["before"]["ledger"]
    after_state = if mode == "ledger", do: step["after"], else: step["after"]["ledger"]

    "Reserved: #{before["used_amount"]}¢ → #{after_state["used_amount"]}¢. Slots: #{before["used_holds"]} → #{after_state["used_holds"]}."
  end

  defp event_label(%{"kind" => "local", "event" => event}), do: "Local " <> event_label(event)
  defp event_label(%{"kind" => kind}), do: "Remote " <> kind

  defp event_label(%{"type" => "request", "key" => key, "amount" => amount}),
    do: "request #{key} · #{amount}¢"

  defp event_label(%{"type" => type, "key" => key}),
    do: String.trim(String.replace(type, "_", " ") <> " #{key}")

  defp check_label("allows_here"), do: "Applies · output satisfies"
  defp check_label("catches"), do: "Applies · rejects candidate"
  defp check_label("doesnt_apply"), do: "Does not apply"
  defp check_label(status), do: "Unresolved · " <> status

  defp event_options("ledger"),
    do:
      ~w(request dispatch timeout restart retry processor_result transport_ack void void_confirmed)

  defp event_options("exposure"),
    do: [
      {"Local request", "request"},
      {"Local dispatch", "dispatch"},
      {"Local timeout", "timeout"},
      {"Local retry", "retry"},
      {"Local restart", "restart"},
      {"Local void", "void"},
      {"Remote authorize", "authorize"},
      {"Observe approval / decline", "observe"},
      {"Remote terminal void", "remote_void"},
      {"Observe terminal confirmation", "confirm"}
    ]
end
