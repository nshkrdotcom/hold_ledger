defmodule HoldLedgerReviewWeb.Part3Live do
  @moduledoc "Identified baseline/proposal review; independent from legacy scenario reviews."
  use HoldLedgerReviewWeb, :live_view

  alias HoldLedgerReview.{
    Adversarial,
    Canonical,
    Part3AIJobs,
    Part3BoundarySearch,
    Part3ContractDelta,
    Part3Diagnostics,
    Part3Docket,
    Part3Editor,
    Part3ProofInspector,
    Part3Runner,
    Part3Snapshots,
    Part3Store,
    TermCodec
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:panels, %{})
     |> assign(
       :finding_form,
       to_form(
         %{
           "lens" => "reading",
           "status" => "unresolved",
           "scope" => "",
           "rationale" => "",
           "change_ids" => [],
           "evidence_ids" => []
         },
         as: :finding
       )
     )
     |> assign(
       :conclusion_form,
       to_form(
         %{
           "outcome" => "needs_policy_or_evidence",
           "scope" => "",
           "rationale" => "",
           "evidence_ids" => []
         },
         as: :conclusion
       )
     )
     |> assign(:package, nil)
     |> assign(:docket, [])
     |> assign(:source_view, %{})
     |> assign(:packages, [])
     |> assign(:snapshots, [])
     |> assign(:freshness, :ok)
     |> assign(:witness, nil)
     |> assign(:editor_error, nil)
     |> assign(:raw_input, "")
     |> assign(:mode, "expert")
     |> assign(:revealed, true)
     |> assign(:ai_consent, false)
     |> assign(:draft_human_revision, nil)
     |> assign(:proof_inspection, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    case Part3Store.get(id) do
      {:ok, package, freshness} ->
        if connected?(socket),
          do: Phoenix.PubSub.subscribe(HoldLedgerReview.PubSub, "part3:" <> id)

        {:noreply,
         socket
         |> assign_package(package)
         |> assign(:freshness, freshness)
         |> assign(:draft_human_revision, package["human_revision"])
         |> seed("P04")}

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Package corrupt or unavailable; no old schema reinterpreted")
         |> push_navigate(to: "/changes")}
    end
  end

  def handle_params(_, _, socket) do
    rows =
      case Part3Store.list() do
        {:ok, list} -> list
        _ -> []
      end

    {:noreply,
     socket
     |> assign(:package, nil)
     |> assign(:docket, [])
     |> assign(:source_view, %{})
     |> assign(:packages, rows)
     |> assign(:snapshots, Part3Snapshots.identities())}
  end

  @impl true
  def handle_event("toggle_panel", %{"panel" => panel}, socket)
      when panel in ~w(editor raw boundary proof ai policy) do
    {:noreply, assign(socket, :panels, Map.update(socket.assigns.panels, panel, true, &(!&1)))}
  end

  def handle_event("finding_draft", %{"finding" => fields}, socket),
    do: {:noreply, assign(socket, :finding_form, to_form(fields, as: :finding))}

  def handle_event("conclusion_draft", %{"conclusion" => fields}, socket),
    do: {:noreply, assign(socket, :conclusion_form, to_form(fields, as: :conclusion))}

  def handle_event("create_package", %{"baseline" => a, "proposal" => b}, socket) do
    case Part3Store.create(a, b) do
      {:ok, p} ->
        {:noreply, push_navigate(socket, to: "/changes/" <> p["id"])}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Package refused: #{inspect(reason)}. Stage exact local source identities in the operator terminal."
         )}
    end
  end

  def handle_event("starting_scenario", %{"seed" => id}, socket) do
    {:noreply, seed(socket, id)}
  end

  def handle_event("presentation", %{"mode" => mode}, socket) when mode in ~w(expert learning) do
    {:noreply, socket |> assign(:mode, mode) |> assign(:revealed, mode == "expert")}
  end

  def handle_event("reveal", _, socket), do: {:noreply, assign(socket, :revealed, true)}

  def handle_event("refresh_human_revision", _, socket) do
    {:noreply, assign(socket, :draft_human_revision, socket.assigns.package["human_revision"])}
  end

  def handle_event("structured_change", %{"action" => _} = params, socket) do
    case Part3Editor.change(socket.assigns.witness, params) do
      {:ok, witness} ->
        {:noreply, edited(socket, witness)}

      {:error, _} ->
        {:noreply,
         assign(
           socket,
           :editor_error,
           "Unsupported field, invalid shape or value. No input was changed."
         )}
    end
  end

  def handle_event("import_json", %{"import" => %{"json" => json}}, socket)
      when byte_size(json) <= 12_000 do
    socket = assign(socket, :raw_input, json)

    with {:ok, value} <- Jason.decode(json),
         {:ok, decoded} <- Adversarial.decode(value),
         {:ok, canonical} <- Adversarial.encode(decoded) do
      {:noreply, edited(socket, canonical)}
    else
      _ ->
        {:noreply,
         assign(
           socket,
           :editor_error,
           "Import refused by the same bounded event/state/output codec. Nothing saved."
         )}
    end
  end

  def handle_event("pin_example", _, socket) do
    case Part3Store.pin(socket.assigns.package["id"], socket.assigns.witness) do
      {:ok, p, _pin} ->
        {:noreply,
         socket
         |> assign_package(p)
         |> put_flash(:info, "Saved example; no result inferred, no question answered")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Example not saved: #{inspect(reason)}")}
    end
  end

  def handle_event("load_pinned", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.package["pinned_examples"], &(&1["id"] == id)) do
      nil -> {:noreply, put_flash(socket, :error, "Pinned example not found")}
      p -> {:noreply, edited(socket, p["witness"])}
    end
  end

  def handle_event("request_ai", %{"ai" => form}, socket) do
    consent = Map.get(form, "consent") == "true"
    socket = push_event(socket, "part3-consent-consumed", %{})

    if socket.assigns.freshness == :ok do
      case Part3AIJobs.request(
             socket.assigns.package["id"],
             socket.assigns.draft_human_revision,
             consent,
             followup_context: followup_context(form)
           ) do
        {:ok, p, _job} ->
          {:noreply,
           socket
           |> assign_package(p)
           |> put_flash(
             :info,
             "One explicitly authorized model proposal requested. Human answers remain separate."
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "No send or job: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Source changed; no send")}
    end
  end

  def handle_event("accept_ai_question", %{"job" => job, "proposal" => proposal}, socket) do
    p = socket.assigns.package

    cmd = %{
      "request_id" => token(),
      "expected_human_revision" => socket.assigns.draft_human_revision,
      "job_id" => job,
      "proposal_id" => proposal
    }

    case Part3Store.accept_question(p["id"], cmd) do
      {:ok, next} ->
        {:noreply,
         socket
         |> assign_package(next)
         |> assign(:draft_human_revision, next["human_revision"])
         |> put_flash(:info, "Question accepted for human review; it has not been answered")}

      {:error, reason} ->
        {:noreply, conflict(socket, reason)}
    end
  end

  def handle_event("use_ai_draft", %{"job" => job, "proposal" => proposal}, socket) do
    candidate =
      with ai when is_map(ai) <-
             Enum.find(
               socket.assigns.package["ai_history"],
               &(&1["id"] == job and &1["status"] == "succeeded")
             ),
           question when is_map(question) <-
             Enum.find(ai["result"]["proposals"], &(&1["proposal_id"] == proposal)),
           witness when is_map(witness) <- question["witness"],
           {:ok, data} <- Adversarial.decode(witness) do
        Adversarial.encode(data)
      end

    case candidate do
      {:ok, witness} ->
        {:noreply,
         edited(socket, witness)
         |> put_flash(
           :info,
           "Model suggestion is an unsaved draft. Explicit pin, replay and human judgment remain separate"
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Model question has no supported candidate draft")}
    end
  end

  def handle_event("try_boundary", %{"id" => id}, socket) do
    case Enum.find(
           Part3BoundarySearch.cases(socket.assigns.package, socket.assigns.witness),
           &(&1["id"] == id)
         ) do
      %{"witness" => witness} -> {:noreply, edited(socket, witness)}
      _ -> {:noreply, put_flash(socket, :error, "Challenge no longer matches this draft")}
    end
  end

  def handle_event("ingest_artifacts", %{"artifacts" => %{"path" => path}}, socket) do
    case Part3Store.ingest_artifacts(socket.assigns.package["id"], path) do
      {:ok, p} ->
        {:noreply,
         socket
         |> assign_package(p)
         |> assign(:proof_inspection, Part3ProofInspector.inspect(p))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Artifact intake refused: #{inspect(reason)}")}
    end
  end

  def handle_event("run_search", _, socket) do
    case Part3Runner.search(socket.assigns.package["id"], socket.assigns.witness) do
      {:ok, _} ->
        {:noreply,
         put_flash(
           socket,
           :info,
           "Bounded search started using isolated replay pairs. Cancel an active attempt to stop; failures stop the search. No result proves equivalence or safety."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Search refused: #{inspect(reason)}")}
    end
  end

  def handle_event("run_comparison", _, socket) do
    p = socket.assigns.package

    if socket.assigns.freshness == :ok and is_nil(p["conclusion"]) do
      case Part3Runner.replay(p["id"], socket.assigns.witness) do
        {:ok, _} ->
          {:noreply,
           put_flash(
             socket,
             :info,
             "Two isolated local executions requested. Evidence appears when each completes; no run is a proof."
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Replay refused: #{inspect(reason)}")}
      end
    else
      {:noreply,
       put_flash(socket, :error, "Read-only package or source drift. No execution launched.")}
    end
  end

  def handle_event("inspect_proof", _, socket) do
    inspection = Part3ProofInspector.inspect(socket.assigns.package)
    {:noreply, assign(socket, :proof_inspection, inspection)}
  end

  def handle_event("verify_full", _, socket) do
    p = socket.assigns.package

    if socket.assigns.freshness == :ok and is_nil(p["conclusion"]) do
      case Part3Runner.verify(p["id"]) do
        {:ok, _} ->
          {:noreply,
           put_flash(
             socket,
             :info,
             "Full existing formal gate requested in a separate process; not proof acceptance yet."
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Verification refused: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Package is read-only")}
    end
  end

  def handle_event("cancel_attempt", %{"id" => id}, socket) do
    case Part3Runner.cancel(socket.assigns.package["id"], id) do
      {:ok, _} ->
        {:noreply,
         put_flash(socket, :info, "Attempt cancelled; interrupted evidence remains visible")}

      _ ->
        {:noreply,
         put_flash(socket, :error, "Attempt already terminal or not owned by this review")}
    end
  end

  def handle_event("record_finding", %{"finding" => form}, socket) do
    p = socket.assigns.package

    cmd = %{
      "request_id" => token(),
      "expected_human_revision" => socket.assigns.draft_human_revision,
      "lens" => form["lens"],
      "status" => form["status"],
      "scope" => form["scope"],
      "rationale" => form["rationale"],
      "change_ids" => Map.get(form, "change_ids", []),
      "evidence_ids" => Map.get(form, "evidence_ids", []),
      "presentation" => socket.assigns.mode,
      "revealed_before_answer" => socket.assigns.revealed
    }

    case Part3Store.finding(p["id"], cmd) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign_package(updated)
         |> assign(:draft_human_revision, updated["human_revision"])
         |> put_flash(:info, "Scoped human finding recorded. Prior findings retained.")}

      {:error, reason} ->
        {:noreply, conflict(socket, reason)}
    end
  end

  def handle_event("conclude", %{"conclusion" => form}, socket) do
    p = socket.assigns.package

    cmd = %{
      "request_id" => token(),
      "expected_human_revision" => socket.assigns.draft_human_revision,
      "outcome" => form["outcome"],
      "scope" => form["scope"],
      "rationale" => form["rationale"],
      "evidence_ids" => Map.get(form, "evidence_ids", []),
      "confirmed" => true
    }

    case Part3Store.conclude(p["id"], cmd) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign_package(updated)
         |> assign(:draft_human_revision, updated["human_revision"])
         |> put_flash(:info, "Human conclusion recorded with scope; not formal acceptance")}

      {:error, reason} ->
        {:noreply, conflict(socket, reason)}
    end
  end

  # These buttons never write directly. The existing store checks source,
  # evidence/change references, strict command shape and human CAS.
  def handle_event("evidence_decision", %{"id" => id, "choice" => choice}, socket) do
    p = socket.assigns.package

    if socket.assigns.freshness == :ok and is_nil(p["conclusion"]) and
         (socket.assigns.mode != "learning" or socket.assigns.revealed) do
      with {:ok, cmd} <-
             Part3Docket.decision(
               p,
               id,
               choice,
               token(),
               socket.assigns.draft_human_revision,
               socket.assigns.mode,
               socket.assigns.revealed
             ),
           {:ok, updated} <- Part3Store.finding(p["id"], cmd) do
        {:noreply,
         socket
         |> assign_package(updated)
         |> assign(:draft_human_revision, updated["human_revision"])
         |> put_flash(
           :info,
           "Human evidence-linked finding recorded; conclusion and formal gate unchanged"
         )}
      else
        {:error, reason} -> {:noreply, conflict(socket, reason)}
      end
    else
      {:noreply, put_flash(socket, :error, "Evidence action read-only or not revealed")}
    end
  end

  @impl true
  def handle_info({:part3_updated, id}, socket) do
    if socket.assigns.package && socket.assigns.package["id"] == id do
      case Part3Store.get(id) do
        {:ok, p, freshness} ->
          {:noreply, socket |> assign_package(p) |> assign(:freshness, freshness)}

        _ ->
          {:noreply, put_flash(socket, :error, "Saved package no longer readable")}
      end
    else
      {:noreply, socket}
    end
  end

  defp assign_package(socket, package) do
    socket
    |> assign(:package, package)
    |> assign(:docket, Part3Docket.cards(package))
    |> assign(:source_view, source_view(package))
  end

  defp source_view(package) do
    case Part3ContractDelta.presentation(package) do
      {:ok, rows} -> rows
      _ -> %{}
    end
  end

  defp followup_context(%{"mode" => "followup"} = form),
    do: %{"finding_id" => form["finding_id"], "question_id" => form["question_id"]}

  defp followup_context(_), do: nil

  defp conflict(socket, reason) do
    put_flash(
      socket,
      :error,
      "Not saved (#{inspect(reason)}). Another tab or job may have changed the revision; your on-screen draft is unchanged. Check the saved history before submitting again."
    )
  end

  defp seed(socket, id) do
    case Adversarial.seed(id) do
      {:ok, witness} -> edited(socket, witness)
      _ -> put_flash(socket, :error, "Unknown starting scenario")
    end
  end

  defp edited(socket, witness) do
    socket
    |> assign(:witness, witness)
    |> assign(:raw_input, Jason.encode!(witness, pretty: true))
    |> assign(:editor_error, nil)
    |> assign(:revealed, socket.assigns.mode == "expert")
  end

  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

  defp matching_replays(package, witness) do
    digest = Canonical.digest(witness)

    matches =
      Enum.filter(
        package["replay_attempts"],
        &(&1["input_digest"] == digest and &1["status"] == "succeeded")
      )

    a =
      Enum.reverse(matches)
      |> Enum.find(&(&1["snapshot_id"] == package["baseline"]["snapshot_id"]))

    b =
      Enum.reverse(matches)
      |> Enum.find(&(&1["snapshot_id"] == package["proposal"]["snapshot_id"]))

    if a && b, do: {a["result"], b["result"]}, else: nil
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :params, :map, required: true
  attr :options, :list, default: nil
  attr :editable, :boolean, default: true

  defp edit_field(assigns) do
    assigns = assign(assigns, :form, to_form(Map.put(assigns.params, "value", assigns.value)))

    ~H"""
    <.form for={@form} id={@id <> "-form"} phx-change="structured_change">
      <.input :for={{key, value} <- @params} type="hidden" name={key} value={value} />
      <.input
        :if={is_nil(@options)}
        field={@form[:value]}
        id={@id}
        type="number"
        label={@label}
        min="0"
        max="1000000"
        disabled={!@editable}
      />
      <.input
        :if={@options}
        field={@form[:value]}
        id={@id}
        type="select"
        label={@label}
        options={@options}
        disabled={!@editable}
      />
    </.form>
    """
  end

  attr :section, :string, required: true
  attr :state, :map, required: true
  attr :editable, :boolean, default: true

  defp state_controls(assigns) do
    ~H"""
    <div class="part3-state">
      <div class="part3-fields">
        <.edit_field
          :for={field <- ~w(amount_limit hold_limit used_amount used_holds)}
          id={"#{@section}-#{field}"}
          label={String.replace(field, "_", " ")}
          value={@state[field]}
          params={%{"action" => "state", "section" => @section, "field" => field}}
          editable={@editable}
        />
      </div>
      <p class="muted">
        Entry identities and holding statuses are editable. Used totals are independent.
      </p>
      <div :for={{entry, index} <- Enum.with_index(@state["entries"])} class="part3-entry">
        <.edit_field
          :for={field <- ~w(key amount)}
          id={"#{@section}-#{index}-#{field}"}
          label={field}
          value={entry[field]}
          params={%{"action" => "entry", "section" => @section, "field" => field, "index" => index}}
          editable={@editable}
        />
        <.edit_field
          id={"#{@section}-#{index}-status"}
          label="Status"
          value={entry["status"]}
          options={TermCodec.statuses()}
          params={
            %{"action" => "entry", "section" => @section, "field" => "status", "index" => index}
          }
          editable={@editable}
        />
        <button
          type="button"
          phx-click="structured_change"
          phx-value-action="remove_entry"
          phx-value-section={@section}
          phx-value-index={index}
          disabled={!@editable}
        >Remove entry</button>
      </div>
      <div class="part3-actions">
        <button
          type="button"
          phx-click="structured_change"
          phx-value-action="add_entry"
          phx-value-section={@section}
          disabled={!@editable}
        >Add entry</button>
        <button
          type="button"
          phx-click="structured_change"
          phx-value-action="recalculate"
          phx-value-section={@section}
          disabled={!@editable}
        >Recalculate used totals (explicit)</button>
      </div>
    </div>
    """
  end

  attr :section, :string, required: true
  attr :event, :any, required: true
  attr :editable, :boolean, default: true

  defp event_controls(assigns) do
    ~H"""
    <div class="part3-fields" role="group" aria-label={@section}>
      <.edit_field
        id={"#{@section}-type"}
        label="Event"
        value={@event && @event["type"]}
        options={[{"No event selected", ""} | Enum.map(~w(request dispatch timeout void), &{&1, &1})]}
        params={%{"action" => "event", "section" => @section, "field" => "type"}}
        editable={@editable}
      />
      <.edit_field
        :for={field <- ~w(key amount)}
        :if={@event && (field == "key" || @event["type"] == "request")}
        id={"#{@section}-#{field}"}
        label={field}
        value={@event[field]}
        params={%{"action" => "event", "section" => @section, "field" => field}}
        editable={@editable}
      />
      <button
        :if={@section == "follow_on"}
        type="button"
        phx-click="structured_change"
        phx-value-action="no_follow_on"
        disabled={!@editable}
      >No follow-on event</button>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :triage,
        if(assigns.package, do: Part3Diagnostics.triage(assigns.package), else: [])
      )

    assigns =
      assign(
        assigns,
        :replays,
        if(assigns.package && assigns.witness,
          do: matching_replays(assigns.package, assigns.witness),
          else: nil
        )
      )

    assigns =
      assign(
        assigns,
        :editable,
        assigns.package && assigns.freshness == :ok && is_nil(assigns.package["conclusion"])
      )

    ~H"""
    <Layouts.app flash={@flash}>
      <%= if @package == nil do %>
        <section class="part3-home">
          <p class="eyebrow">Versioned review / local snapshots</p>
          <h1>Review a proposed change against a fixed baseline.</h1>
          <p>
            The governing payment policy is independent of both revisions. Source edits are triggers for review, not demonstrated semantic weakening. Start a separate
            <.link navigate="/workbench">single-version scenario</.link>
            if you only need a what-if.
          </p>
          <h2>Identify two operator-staged local snapshots</h2>
          <p class="muted">
            A snapshot is staged from a trusted local terminal by the documented script. Names or branches are not identities. No uploaded executable source or automatic dependency fetch is accepted.
          </p>
          <form phx-submit="create_package" id="create-change-package" class="part3-create">
            <div>
              <label for="baseline-id">Baseline content identity</label>
              <select id="baseline-id" name="baseline" required><option value="">
                Select baseline
              </option><option :for={id <- @snapshots} value={id}>{String.slice(id, 0, 20)}</option></select>
            </div>
            <div>
              <label for="proposal-id">Proposal content identity</label>
              <select id="proposal-id" name="proposal" required><option value="">
                Select proposal
              </option><option :for={id <- @snapshots} value={id}>{String.slice(id, 0, 20)}</option></select>
            </div>
            <button class="primary" type="submit" disabled={length(@snapshots) < 2}>Create separate versioned review</button>
          </form>
          <h2>Saved change reviews</h2>
          <ul class="review-list" id="part3-package-list">
            <li :for={p <- @packages}>
              <.link navigate={"/changes/" <> p["id"]}>{String.slice(p["baseline_id"], 0, 12)} → {String.slice(
                p["proposal_id"],
                0,
                12
              )}</.link>
              <span>Human revision {p["human_revision"]} · {p["updated_at"]}</span>
            </li>
          </ul>
        </section>
      <% else %>
        <header class="part3-header">
          <p class="eyebrow">Identified proposed change / local operator trust</p>
          <h1>What promise changed?</h1>
          <p>
            <b>Baseline</b>
            <code>{@package["baseline"]["snapshot_id"]}</code><small>{if @package["baseline"][
                                                                           "dirty"
                                                                         ],
                                                                         do: "dirty captured bytes",
                                                                         else: "committed clean bytes"}</small>
          </p>
          <p>
            <b>Proposal</b>
            <code>{@package["proposal"]["snapshot_id"]}</code><small>{if @package["proposal"][
                                                                           "dirty"
                                                                         ],
                                                                         do: "dirty captured bytes",
                                                                         else: "committed clean bytes"}</small>
          </p>
          <nav aria-label="Review navigation">
            <.link navigate="/changes">All change reviews</.link>
            · <.link navigate="/workbench">Single-version review</.link>
          </nav>
          <p :if={@freshness != :ok} role="alert" class="notice-alert">
            Source or toolchain drift: this historical package is read-only. An old answer is not rebound to new bytes.
          </p>
          <p :if={@package["conclusion"]} class="notice-alert">
            Human conclusion recorded: {@package["conclusion"]["outcome"]}. Read-only; not formal acceptance.
          </p>
          <div class="part3-presentation" aria-label="Presentation mode">
            <button
              type="button"
              phx-click="presentation"
              phx-value-mode="expert"
              aria-pressed={to_string(@mode == "expert")}
            >Expert: evidence first</button>
            <button
              type="button"
              phx-click="presentation"
              phx-value-mode="learning"
              aria-pressed={to_string(@mode == "learning")}
            >Learning: predict first</button>
          </div>
        </header>
        <main class="part3-main">
          <section class="part3-primary" aria-label="Decision and evidence">
            <h2>Relevant source changes <small>{length(@package["source_changes"])} paths</small></h2>
            <p :if={@package["source_changes"] == []}>
              No source differences in these identified manifests. This does not prove semantic equivalence.
            </p>
            <ol class="part3-changes" id="part3-source-delta">
              <li :for={change <- @package["source_changes"]} id={"change-" <> change["id"]}>
                <details>
                  <summary>
                    <code>{change["path"]}</code>
                    · {String.replace(change["kind"], "_", " ")} · structural source edit
                  </summary>
                  <p :if={change["claim"]["analysis"] == "supported_structural_ast"} class="muted">
                    Normalized condition changed: {to_string(change["claim"]["changed"]["conditions"])};
                    normalized promise changed: {to_string(change["claim"]["changed"]["promises"])}.
                    A syntactic edit alone cannot establish a narrowed domain or weaker promise.
                  </p>
                  <p :if={change["claim"]["analysis"] != "supported_structural_ast"} class="muted">
                    {change["claim"]["reason"] ||
                      "Helper, Lean or other unclassified source edit; inspect full source."}
                  </p>
                  <div
                    :for={expr <- get_in(@source_view, [change["id"], "expressions"]) || []}
                    class="part3-expression"
                  >
                    <h3>Normalized {expr["label"]} · {expr["status"]}</h3>
                    <div class="part3-sources">
                      <div>
                        <b>Baseline normalized AST</b><pre><%= for chunk <- expr["baseline"] do %><del :if={chunk["kind"] == "del"}>{chunk["text"]}</del><span :if={chunk["kind"] == "eq"}>{chunk["text"]}</span><% end %></pre>
                      </div>
                      <div>
                        <b>Proposal normalized AST</b><pre><%= for chunk <- expr["proposal"] do %><ins :if={chunk["kind"] == "ins"}>{chunk["text"]}</ins><span :if={chunk["kind"] == "eq"}>{chunk["text"]}</span><% end %></pre>
                      </div>
                    </div>
                  </div>
                  <div class="part3-sources">
                    <div>
                      <h3>Baseline · exact source context</h3>
                      <p class="muted">
                        From line {get_in(@source_view, [change["id"], "baseline", "start_line"]) ||
                          "unavailable"}, bounded context.
                      </p>
                      <pre>{get_in(@source_view, [change["id"], "baseline", "text"]) || "Source unavailable or stale"}</pre>
                      <.link
                        :if={@freshness == :ok && change["baseline_sha256"]}
                        href={"/changes/#{@package["id"]}/source/baseline/#{change["id"]}"}
                      >Open complete verified baseline file</.link>
                    </div>
                    <div>
                      <h3>Proposal · exact source context</h3>
                      <p class="muted">
                        From line {get_in(@source_view, [change["id"], "proposal", "start_line"]) ||
                          "unavailable"}, bounded context.
                      </p>
                      <pre>{get_in(@source_view, [change["id"], "proposal", "text"]) || "Source unavailable or stale"}</pre>
                      <.link
                        :if={@freshness == :ok && change["proposal_sha256"]}
                        href={"/changes/#{@package["id"]}/source/proposal/#{change["id"]}"}
                      >Open complete verified proposal file</.link>
                    </div>
                  </div>
                  <p
                    :for={span <- get_in(@source_view, [change["id"], "declarations"]) || []}
                    class="muted"
                  >
                    {span["side"]} parser declaration span: {span["start_line"] || "unavailable"}–{span[
                      "end_line"
                    ] || "unavailable"} ({span["kind"]}). Normalized expressions are not source-byte reproductions.
                  </p>
                  <small>Exact file digests: {change["baseline_sha256"] || "absent"} / {change[
                    "proposal_sha256"
                  ] || "absent"}.
                  Semantic relation: {change["semantic_relation"]}; {get_in(@source_view, [
                    change["id"],
                    "status"
                  ]) || "unavailable_or_stale_source"}.</small>
                </details>
              </li>
            </ol>
            <section class="part3-comparison" id="part3-comparison">
              <h2>Concrete example and isolated execution</h2>
              <p>
                Both runs require the same valid starting ledger and typed candidate. A wrong but structurally representable outcome is allowed; incorrect accounting is not silently repaired.
              </p>
              <div class="part3-actions">
                <button
                  :for={seed <- Adversarial.seeds()}
                  type="button"
                  phx-click="starting_scenario"
                  phx-value-seed={seed}
                >{seed}</button>
              </div>
              <div :if={@witness} class="part3-sides">
                <div>
                  <b>Input/event</b><p>
                    {@witness["event"]["type"]} / key {@witness["event"]["key"]}
                  </p><p>
                    Amount limit {@witness["before"]["amount_limit"]}, in use {@witness["before"][
                      "used_amount"
                    ]}
                  </p>
                </div>
                <div>
                  <b>Proposed outcome to challenge</b><p>Result {@witness["output"]["result"]}</p><p>
                    Used amount {@witness["output"]["after"]["used_amount"]}, holds {@witness[
                      "output"
                    ]["after"]["used_holds"]}
                  </p>
                </div>
              </div>
              <%= if @mode == "learning" && !@revealed do %>
                <p>
                  Predict whether an exact-fit input belongs to each version's promise, and whether the candidate should be permitted. Predictions are not secretly collected.
                </p>
                <button type="button" phx-click="reveal" id="part3-reveal">Show computed evidence</button>
              <% else %>
                <%= if @replays do %>
                  <div class="part3-sides" id="part3-replay-result">
                    <div>
                      <h3>Baseline actual</h3><pre>{Jason.encode!(elem(@replays, 0)["evaluation"]["actual"], pretty: true)}</pre>
                    </div>
                    <div>
                      <h3>Proposal actual</h3><pre>{Jason.encode!(elem(@replays, 1)["evaluation"]["actual"], pretty: true)}</pre>
                    </div>
                  </div>
                  <p class="muted">
                    Pointwise observations for this exact draft only. A contract-only permitted alternative does not mean the implementation produced it.
                  </p>
                <% else %>
                  <p id="part3-missing-replay" class="muted">
                    No completed pair of isolated executions for this exact draft. Source comparison remains structural; replay is NOT RUN or pending.
                  </p>
                <% end %>
                <div id="part3-evidence-list" class="part3-docket">
                  <article
                    :for={card <- @docket}
                    id={"evidence-" <> card["id"]}
                    class="part3-evidence-card"
                  >
                    <h3>{String.replace(card["kind"], "_", " ")} · identified pointwise evidence</h3>
                    <p>{card["evidence"]["note"]} Not a general theorem or policy decision.</p>
                    <small>{card["id"]} · {card["evidence"]["method"]} · baseline/proposal source IDs fixed by package.</small>
                    <details>
                      <summary>Show exact input and independent candidate output</summary>
                      <h4>Input (same for both executions)</h4>
                      <pre>{Jason.encode!(card["evidence"]["input"], pretty: true)}</pre>
                      <h4>Deliberate candidate output (not observed)</h4>
                      <pre>{if card["evidence"]["output"], do: Jason.encode!(card["evidence"]["output"], pretty: true), else: "Not supplied for this distinction"}</pre>
                    </details>
                    <div class="part3-sides">
                      <div>
                        <b>Baseline comparison evidence</b>
                        <pre>{if card["evidence"]["baseline_result"], do: Jason.encode!(card["evidence"]["baseline_result"], pretty: true), else: "Not supplied"}</pre>
                        <b>Baseline actual Ledger output</b>
                        <pre>{if card["receipts"]["baseline"]["actual"], do: Jason.encode!(card["receipts"]["baseline"]["actual"], pretty: true), else: "No admitted matching replay"}</pre>
                      </div>
                      <div>
                        <b>Proposal comparison evidence</b>
                        <pre>{if card["evidence"]["proposal_result"], do: Jason.encode!(card["evidence"]["proposal_result"], pretty: true), else: "Not supplied"}</pre>
                        <b>Proposal actual Ledger output</b>
                        <pre>{if card["receipts"]["proposal"]["actual"], do: Jason.encode!(card["receipts"]["proposal"]["actual"], pretty: true), else: "No admitted matching replay"}</pre>
                      </div>
                    </div>
                    <p class="muted">
                      Directly matched changed declarations (not causal proof): {card[
                        "correspondence"
                      ]}.
                    </p>
                    <ul>
                      <li :for={change <- card["changes"]}>
                        <a href={"#change-" <> change["id"]}>{change["path"]}</a> · {change["id"]}
                      </li>
                    </ul>
                    <p>
                      Latest human disposition: {if card["latest"],
                        do: card["latest"]["status"],
                        else: "unresolved / no recorded finding"}.
                    </p>
                    <details :if={card["history"] != []}>
                      <summary>
                        Immutable human finding history · {length(card["history"])} records
                      </summary>
                      <ol>
                        <li :for={f <- card["history"]}>
                          Revision {f["human_revision"]}, {f["status"]}: {f["rationale"]}
                        </li>
                      </ol>
                    </details>
                    <div class="part3-actions">
                      <button
                        type="button"
                        phx-click="evidence_decision"
                        phx-value-id={card["id"]}
                        phx-value-choice="design"
                        disabled={!@editable}
                      >Record needs design change</button>
                      <button
                        type="button"
                        phx-click="evidence_decision"
                        phx-value-id={card["id"]}
                        phx-value-choice="policy"
                        disabled={!@editable}
                      >Needs policy/evidence decision</button>
                      <button
                        type="button"
                        phx-click="evidence_decision"
                        phx-value-id={card["id"]}
                        phx-value-choice="considered"
                        disabled={!@editable}
                      >Mark considered in scope (not fixed)</button>
                    </div>
                    <div :if={@freshness == :ok} class="part3-actions">
                      <.link href={"/changes/#{@package["id"]}/repair/#{card["id"]}.md"}>Download local repair packet (Markdown)</.link>
                      <.link href={"/changes/#{@package["id"]}/repair/#{card["id"]}.json"}>Strict JSON</.link>
                    </div>
                  </article>
                  <p :if={@docket == []}>
                    No admitted distinction yet. Run the isolated pair; an absence of findings is not evidence of equivalence.
                  </p>
                </div>
              <% end %>
              <div class="part3-actions">
                <button type="button" phx-click="pin_example" id="part3-pin" disabled={!@editable}>Save/pin this draft (no execution)</button>
                <button
                  type="button"
                  phx-click="run_comparison"
                  id="run-isolated-replay"
                  class="primary"
                  disabled={!@editable}
                >Run both identified versions locally</button>
              </div>
              <details id="part3-pins">
                <summary>Saved example drafts · {length(@package["pinned_examples"])}</summary>
                <ul>
                  <li :for={pin <- @package["pinned_examples"]}>
                    <button type="button" phx-click="load_pinned" phx-value-id={pin["id"]}>Open example {String.slice(
                      pin["input_digest"],
                      0,
                      16
                    )}</button>
                    · saved {pin["pinned_at"]}
                  </li>
                </ul>
              </details>
              <h3>Execution attempts and failures</h3>
              <ul id="part3-replay-attempts">
                <li :for={a <- @package["replay_attempts"]}>
                  {String.slice(a["snapshot_id"], 0, 12)} · {a["status"]} · {a["diagnostics"]} · {a[
                    "scope"
                  ]}
                  <button
                    :if={a["status"] in ~w(queued running)}
                    type="button"
                    phx-click="cancel_attempt"
                    phx-value-id={a["id"]}
                  >Cancel</button>
                </li>
              </ul>
            </section>
            <section id="part3-decision">
              <h2>Human finding beside the evidence</h2>
              <p
                :if={@draft_human_revision != @package["human_revision"]}
                role="alert"
                class="notice-alert"
              >
                Another tab has recorded a human decision. Your form is not silently rebound. Inspect the saved answer, then deliberately
                <button type="button" phx-click="refresh_human_revision">use the current human revision</button>
                to submit.
              </p>
              <p>
                Each lens remains reviewable even with no automatic trigger. An absent trigger is not evidence that the requirement is inapplicable.
              </p>
              <dl :for={lens <- @triage} class="part3-lens">
                <dt><b>{String.replace(lens["lens"], "_", " ")}</b> · {lens["status"]}</dt>
                <dd>
                  {lens["question"]}<small>{length(lens["changes"])} relevant source edits · {lens[
                    "triage"
                  ]}</small>
                </dd>
                <dd :if={lens["latest"]}>
                  <b>Last human reason:</b> {lens["latest"]["rationale"]} · revealed before answer: {to_string(
                    lens["latest"]["revealed_before_answer"]
                  )}
                </dd>
              </dl>
              <.form
                for={@finding_form}
                id="part3-finding"
                phx-change="finding_draft"
                phx-submit="record_finding"
                class="part3-judgment"
              >
                <.input
                  field={@finding_form[:lens]}
                  id="part3-lens"
                  type="select"
                  label="Concern to address"
                  options={Enum.map(@triage, &{String.replace(&1["lens"], "_", " "), &1["lens"]})}
                  required
                />
                <.input
                  field={@finding_form[:status]}
                  id="part3-finding-status"
                  type="select"
                  label="Finding status"
                  options={[
                    {"Unresolved", "unresolved"},
                    {"Addressed in stated scope", "addressed"},
                    {"Not applicable (give reason)", "not_applicable"}
                  ]}
                />
                <.input
                  field={@finding_form[:scope]}
                  id="part3-finding-scope"
                  label="Scope actually reviewed"
                  required
                  maxlength="600"
                />
                <.input
                  field={@finding_form[:rationale]}
                  id="part3-finding-rationale"
                  type="textarea"
                  label="Policy-based rationale / missing evidence"
                  required
                  minlength="5"
                  maxlength="1200"
                  rows="3"
                />
                <details>
                  <summary>Attach changed source and computed evidence IDs</summary>
                  <label :for={c <- @package["source_changes"]}><input
                    type="checkbox"
                    name="finding[change_ids][]"
                    value={c["id"]}
                    checked={c["id"] in (@finding_form.params["change_ids"] || [])}
                  />{c["path"]}</label>
                  <label :for={e <- @package["evidence"]}><input
                    type="checkbox"
                    name="finding[evidence_ids][]"
                    value={e["id"]}
                    checked={e["id"] in (@finding_form.params["evidence_ids"] || [])}
                  />{e["kind"]} / {e["id"]}</label>
                </details>
                <button type="submit" disabled={!@editable}>Record human finding</button>
              </.form>
              <details>
                <summary>Prior human findings and revision history</summary>
                <ol>
                  <li :for={f <- @package["human_findings"]}>
                    <b>{f["lens"]}: {f["status"]}</b>
                    · revision {f["human_revision"]}
                    <p>{f["rationale"]}</p>
                  </li>
                </ol>
              </details>
              <details id="part3-accepted-questions">
                <summary>Deliberately accepted model questions (not answers)</summary>
                <ul>
                  <li :for={q <- @package["accepted_questions"]}>
                    <b>{q["kind"]}</b>
                    · {q["question"]}<small> accepted human revision {q["human_revision"]}</small>
                  </li>
                </ul>
              </details>
              <h3>Separate human conclusion</h3>
              <.form
                for={@conclusion_form}
                id="part3-conclude"
                phx-change="conclusion_draft"
                phx-submit="conclude"
                class="part3-judgment"
              >
                <.input
                  field={@conclusion_form[:outcome]}
                  id="part3-outcome"
                  type="select"
                  label="Conclusion"
                  options={[
                    {"Needs policy or evidence", "needs_policy_or_evidence"},
                    {"Needs design change", "needs_design_change"},
                    {"Meets intent only in reviewed scope", "meets_intent_in_reviewed_scope"}
                  ]}
                />
                <.input
                  field={@conclusion_form[:scope]}
                  id="part3-scope"
                  label="Reviewed scope"
                  required
                  maxlength="600"
                />
                <.input
                  field={@conclusion_form[:rationale]}
                  id="part3-rationale"
                  type="textarea"
                  label="Reason"
                  required
                  minlength="5"
                  maxlength="1200"
                  rows="3"
                />
                <details>
                  <summary>Attach computed evidence</summary><label :for={e <- @package["evidence"]}><input
                    type="checkbox"
                    name="conclusion[evidence_ids][]"
                    value={e["id"]}
                    checked={e["id"] in (@conclusion_form.params["evidence_ids"] || [])}
                  />{e["kind"]}</label>
                </details>
                <button type="submit" id="part3-finish" disabled={!@editable}>Confirm my conclusion (not proof acceptance)</button>
              </.form>
            </section>
          </section>
          <aside class="part3-context" aria-label="Edit example and inspect proof details">
            <details id="part3-structured-editor" open={@panels["editor"]}>
              <summary phx-click="toggle_panel" phx-value-panel="editor">
                <b>Edit the example</b> · structured controls
              </summary>
              <details id="part3-boundary-search" open={@panels["boundary"]}>
                <summary phx-click="toggle_panel" phx-value-panel="boundary">
                  Bounded change-directed challenges
                </summary>
                <p>
                  Challenge changed helpers, conditions and inventories with amounts, statuses, identities, effects/frame and two-event consequences. Up to 48 cases. Native-only bindings, unsupported correspondence and general solver results remain unresolved.
                </p>
                <button
                  type="button"
                  id="part3-run-search"
                  phx-click="run_search"
                  disabled={!@editable}
                >Run bounded isolated search (up to 48 cases; cancel stops)</button>
                <div class="part3-actions">
                  <button
                    :for={item <- Part3BoundarySearch.cases(@package, @witness)}
                    type="button"
                    phx-click="try_boundary"
                    phx-value-id={item["id"]}
                    disabled={!@editable}
                  >{item["label"]} · amount {item["requested_amount"]}</button>
                </div>
              </details>
              <p :if={@editor_error} class="notice-alert" role="alert">{@editor_error}</p>
              <%= if @witness do %>
                <h3>Valid starting ledger required for execution</h3>
                <.state_controls section="before" state={@witness["before"]} editable={@editable} />
                <h3>Event</h3><.event_controls
                  section="event"
                  event={@witness["event"]}
                  editable={@editable}
                />
                <h3>Candidate after-state · counters may be intentionally wrong</h3>
                <.state_controls
                  section="candidate"
                  state={@witness["output"]["after"]}
                  editable={@editable}
                />
                <.edit_field
                  id="part3-result"
                  label="Candidate result"
                  value={@witness["output"]["result"]}
                  options={TermCodec.results()}
                  params={%{"action" => "result"}}
                  editable={@editable}
                />
                <h3>Requested external effects (not performed)</h3>
                <div
                  :for={{effect, index} <- Enum.with_index(@witness["output"]["effects"])}
                  class="part3-fields"
                >
                  <.edit_field
                    id={"effect-type-#{index}"}
                    label="Effect type"
                    value={effect["type"]}
                    options={~w(void authorize)}
                    params={%{"action" => "effect", "field" => "type", "index" => index}}
                    editable={@editable}
                  />
                  <.edit_field
                    :for={field <- ~w(key amount)}
                    :if={field == "key" || effect["type"] == "authorize"}
                    id={"effect-#{field}-#{index}"}
                    label={field}
                    value={effect[field]}
                    params={%{"action" => "effect", "field" => field, "index" => index}}
                    editable={@editable}
                  />
                  <button
                    type="button"
                    phx-click="structured_change"
                    phx-value-action="remove_effect"
                    phx-value-index={index}
                    disabled={!@editable}
                  >Remove effect</button>
                </div>
                <button
                  type="button"
                  phx-click="structured_change"
                  phx-value-action="add_effect"
                  disabled={!@editable}
                >Add effect</button>
                <h3>Optional next event</h3><.event_controls
                  section="follow_on"
                  event={@witness["follow_on"]}
                  editable={@editable}
                />
                <details id="part3-advanced-json" open={@panels["raw"]}>
                  <summary phx-click="toggle_panel" phx-value-panel="raw">
                    Advanced JSON · same strict codec for import
                  </summary>
                  <pre id="part3-export-json">{Jason.encode!(@witness, pretty: true)}</pre>
                  <form phx-submit="import_json" id="part3-import">
                    <label for="part3-raw">Import edited example</label><textarea
                      id="part3-raw"
                      name="import[json]"
                      rows="8"
                      maxlength="12000"
                    >{@raw_input}</textarea><button type="submit" disabled={!@editable}>Validate and load as unsaved draft</button>
                  </form>
                </details>
              <% end %>
            </details>
            <details id="part3-proof" open={@panels["proof"]}>
              <summary phx-click="toggle_panel" phx-value-panel="proof">
                <b>Proof artifacts and provenance</b> · inspect separately
              </summary>
              <p>
                Formal acceptance is derived only by the repository's full required-scope source-matching report validator. An axiom name or no `sorry` does not establish acceptance.
              </p>
              <button type="button" phx-click="inspect_proof" id="part3-inspect-proof">Inspect registered source and checked artifacts</button>
              <%= case @proof_inspection do %>
                <% {:ok, inspected} -> %>
                  <p id="part3-proof-inspection">
                    Proposal registered obligations: {inspected["catalog_count"]}.
                    Original report validator status: {inspected["formal_acceptance"]}.
                    These are recorded, source-bound reports, not newly run checkers.
                  </p>
                  <details :for={version <- inspected["versions"]} class="part3-proof-version">
                    <summary>
                      {String.capitalize(version["side"])} · {version["catalog_count"]} obligations · report {version[
                        "report_status"
                      ]} · original-gate status {version["formal_acceptance"]}
                    </summary>
                    <p>Snapshot identity: <code>{version["snapshot_id"]}</code></p>
                    <p :if={version["report_reference"]} class="muted">
                      Recorded report: {version["report_reference"]["path"]} / SHA-256 {version[
                        "report_reference"
                      ]["sha256"]}.
                      Producer assertions alone do not certify acceptance.
                    </p>
                    <p :if={!version["report_reference"]} class="muted">
                      No matching, validated report supplied for this version; all independent checker outcomes: NOT RUN / unavailable.
                    </p>
                    <details :for={item <- version["sources"]} class="part3-proof-law">
                      <summary>{item["slug"]} · {item["purpose"]} · {item["artifact_scope"]}</summary>
                      <p>
                        Registered {version["side"]} source: {item["source"]["path"]} / {item[
                          "source"
                        ]["sha256"] || "unavailable"} · {item["source"]["status"]}.
                      </p>
                      <.link
                        :if={@freshness == :ok && item["source"]["status"] == "source_hash_matched"}
                        href={"/changes/#{@package["id"]}/law/#{version["side"]}/#{item["slug"]}/source"}
                      >Open complete registered claim or Lean file</.link>
                      <pre>{item["source"]["excerpt"] || "Source is unavailable"}</pre>
                      <p :if={item["source"]["excerpt_bounded"]} class="muted">
                        Bounded preview only; use the complete-file link above.
                      </p>
                      <h4>Translated statement (producer-provided)</h4>
                      <pre>{if item["translated_statement"], do: inspect(item["translated_statement"]), else: "Not supplied (do not infer from the source claim)"}</pre>
                      <h4>Lean declaration / theorem artifacts</h4>
                      <p :if={item["lean_declarations"] == []}>
                        No declaration-level text supplied for this obligation.
                      </p>
                      <p :for={a <- item["lean_declarations"]}>
                        {a["kind"]} · {a["path"]} · {a["status"]}
                      </p>
                      <h4>Proof dependencies</h4>
                      <pre>{if item["proof_dependencies"], do: inspect(item["proof_dependencies"]), else: "Not supplied at theorem level"}</pre>
                      <p :for={a <- item["dependency_artifacts"]}>
                        Dependency artifact {a["path"]} · {a["status"]}
                      </p>
                      <h4>Original producer export, axioms and six checker records</h4>
                      <p :if={item["exports"] == []}>
                        No checker/export records supplied for this law. Status: NOT RUN / unavailable.
                      </p>
                      <div :for={export <- item["exports"]} class="part3-proof-export">
                        <p>
                          Export scope: <b>{export["scope"]}</b>
                          (axioms {export["axiom_scope"]}); path {export["path"]}; hash {export[
                            "sha256"
                          ] || "not supplied"}.
                        </p>
                        <p>
                          Original gate: <b>{export["original_gate_status"]}</b>; producer reported pass: {inspect(
                            export["producer_passed"]
                          )}.
                        </p>
                        <p>
                          Recorded axiom list (not a theorem-specific audit): {inspect(
                            export["recorded_axioms"] || "not supplied"
                          )}.
                          Allowed policy: propext, Quot.sound, Classical.choice. No lexical scan is an acceptance gate.
                        </p>
                        <ul>
                          <li :for={checker <- export["checkers"]}>
                            {checker["name"]}: {checker["recorded_status"]}
                          </li>
                        </ul>
                      </div>
                      <h4>Other attached artifacts (bounded previews)</h4>
                      <details :for={artifact <- item["artifacts"]}>
                        <summary>
                          {artifact["kind"] || "report"} · {artifact["path"]} · {artifact["status"]}
                        </summary>
                        <p>
                          SHA-256 {artifact["sha256"]} · {artifact["bytes"]} bytes · presence is not acceptance.
                        </p>
                        <pre>{artifact["excerpt"] || "Artifact missing or stale"}</pre>
                        <.link
                          :if={@freshness == :ok && artifact["status"] == "present"}
                          href={"/changes/#{@package["id"]}/artifact/#{version["side"]}/#{artifact["sha256"]}"}
                        >Open complete locally verified artifact</.link>
                      </details>
                    </details>
                    <details :if={version["artifacts"] != []}>
                      <summary>
                        All {version["side"]} artifacts, including report-level records
                      </summary>
                      <ul>
                        <li :for={a <- version["artifacts"]}>
                          {a["path"]} · {a["status"]} · {a["sha256"]}
                          <.link
                            :if={@freshness == :ok && a["status"] == "present"}
                            href={"/changes/#{@package["id"]}/artifact/#{version["side"]}/#{a["sha256"]}"}
                          >Full verified file</.link>
                        </li>
                      </ul>
                    </details>
                  </details>
                <% {:error, reason} -> %>
                  <p role="alert">
                    Proof inspection unavailable: {inspect(reason)}. No new acceptance inferred.
                  </p>
                <% _ -> %>
                  <p>
                    Open the inspector to read original registered source and any matching artifacts separately for baseline and proposal. Missing translation, exports or dependencies stay missing.
                  </p>
              <% end %>
              <.form
                for={to_form(%{}, as: :artifacts)}
                id="part3-artifact-intake"
                phx-submit="ingest_artifacts"
              >
                <.input
                  type="text"
                  name="artifacts[path]"
                  value=""
                  label="Operator-staged artifact index path (tmp/verification/part3-…/)"
                />
                <button type="submit" disabled={!@editable}>Inspect and retain incremental offline/CI artifacts</button>
              </.form>
              <button
                type="button"
                phx-click="verify_full"
                id="part3-run-formal"
                disabled={!@editable}
              >Request full existing verification gate</button>
              <ul id="part3-verification-attempts">
                <li :for={a <- @package["verification_attempts"]}>
                  <b>{a["kind"]} · {a["status"]}</b>
                  · {a["diagnostics"]}
                  <small>{a["producer"]} / {a["scope"]} / {a["snapshot_id"]}</small>
                  <small :for={artifact <- a["artifacts"]}>{artifact["path"]} / {artifact["sha256"]}</small>
                  <button
                    :if={a["status"] in ~w(queued running)}
                    type="button"
                    phx-click="cancel_attempt"
                    phx-value-id={a["id"]}
                  >Cancel</button>
                </li>
              </ul>
              <p :if={@package["verification_attempts"] == []}>
                No proposal formal verification supplied or run. Elaboration, export, independent checkers and full acceptance: NOT RUN.
              </p>
              <details>
                <summary>Lean, translation, dependency and inventory source changes</summary>
                <p
                  :for={c <- @package["source_changes"]}
                  :if={
                    c["kind"] in ~w(lean_declaration_or_dependency translation_or_elaboration obligation_or_inventory)
                  }
                >
                  {c["path"]} · source digest {c["proposal_sha256"]} · proof/dependency meaning requires human inspection
                </p>
                <p>
                  Translated theorems, proof dependencies and checker exports are not fabricated when artifacts are absent.
                </p>
              </details>
            </details>
            <details id="part3-policy" open={@panels["policy"]}>
              <summary phx-click="toggle_panel" phx-value-panel="policy">
                <b>Governing policy and review limits</b>
              </summary>
              <p :for={policy <- @package["policy_anchors"]}>
                {policy["authority"]}: {policy["path"]} ({policy["passage"]}) · digest
                <code>{policy["sha256"]}</code>
              </p>
              <p>
                Process separation prevents module mixing, not malicious code. Only locally staged operator-trusted source can execute. A changed code representation needs explicit correspondence; unsupported general implications remain unresolved.
              </p>
            </details>
            <details id="part3-ai" open={@panels["ai"]}>
              <summary phx-click="toggle_panel" phx-value-panel="ai">
                <b>Optional AI proposer</b> · consent required for every send
              </summary>
              <p>
                Only bounded policy and identified source excerpts plus typed evidence summaries are sent if you authorize this particular request. Discovery excludes human answers. Follow-up sends the selected recorded finding, accepted question and linked evidence, explicitly attributed to you. Conclusions, private benchmarks, hidden rubrics and credentials are excluded. A model question is not an independent finding.
              </p>
              <p id="part3-ai-no-consent">
                Consent defaults to off on every page load. No auto resend on reload or reconnect. The existing Inference ASM/Codex model is unchanged; unavailable credentials mean no send.
              </p>
              <form phx-submit="request_ai" id="part3-ai-request" class="part3-judgment">
                <label for="part3-ai-mode">Request context</label>
                <select id="part3-ai-mode" name="ai[mode]"><option value="discovery">
                  Source-only discovery
                </option><option value="followup">
                  Answer-aware follow-up (selected recorded context)
                </option></select>
                <label for="part3-ai-finding">Recorded human finding for follow-up</label>
                <select id="part3-ai-finding" name="ai[finding_id]"><option value="">
                  Select finding
                </option><option :for={f <- @package["human_findings"]} value={f["id"]}>
                  {f["lens"]} · revision {f["human_revision"]}
                </option></select>
                <label for="part3-ai-question">Accepted question for follow-up</label>
                <select id="part3-ai-question" name="ai[question_id]"><option value="">
                  Select accepted question
                </option><option :for={q <- @package["accepted_questions"]} value={q["id"]}>
                  {q["question"]}
                </option></select>
                <label for="part3-ai-consent"><input
                  id="part3-ai-consent"
                  phx-hook="Part3Consent"
                  phx-update="ignore"
                  type="checkbox"
                  name="ai[consent]"
                  value="true"
                  required
                />Authorize one package-source send now</label>
                <button type="submit" disabled={!@editable}>Request model questions (optional)</button>
              </form>
              <ul id="part3-ai-jobs">
                <li :for={job <- @package["ai_history"]}>
                  <p>
                    Model proposal · {job["status"]} · requested under human revision {job[
                      "human_revision_at_request"
                    ]} · {job["error"]}
                  </p>
                  <%= if job["result"] do %>
                    <div :for={proposal <- job["result"]["proposals"]} class="part3-model-question">
                      <b>{proposal["kind"]}</b><p>{proposal["question"]}</p><p class="muted">
                        {proposal["rationale"]}
                      </p>
                      <div class="part3-actions">
                        <button
                          type="button"
                          phx-click="use_ai_draft"
                          phx-value-job={job["id"]}
                          phx-value-proposal={proposal["proposal_id"]}
                          disabled={
                            !@editable || is_nil(proposal["witness"]) || job["status"] != "succeeded"
                          }
                        >Use suggested case as unsaved draft</button>
                        <button
                          type="button"
                          phx-click="accept_ai_question"
                          phx-value-job={job["id"]}
                          phx-value-proposal={proposal["proposal_id"]}
                          disabled={!@editable || job["status"] != "succeeded"}
                        >Accept question only</button>
                      </div>
                    </div>
                  <% end %>
                </li>
              </ul>
            </details>
          </aside>
        </main>
      <% end %>
    </Layouts.app>
    """
  end
end
