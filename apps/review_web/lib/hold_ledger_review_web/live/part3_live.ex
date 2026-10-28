defmodule HoldLedgerReviewWeb.Part3Live do
  @moduledoc "Identified baseline/proposal review; independent from legacy scenario reviews."
  use HoldLedgerReviewWeb, :live_view
  alias HoldLedgerReview.{Adversarial, Canonical, Part3AIJobs, Part3BoundarySearch, Part3Diagnostics, Part3Editor, Part3Package, Part3ProofInspector, Part3Runner, Part3Snapshots, Part3Store, TermCodec}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:package, nil)
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
        if connected?(socket), do: Phoenix.PubSub.subscribe(HoldLedgerReview.PubSub, "part3:" <> id)
        {:noreply, socket |> assign(:package, package) |> assign(:freshness, freshness) |> assign(:draft_human_revision, package["human_revision"]) |> seed("P04")}
      _ -> {:noreply, socket |> put_flash(:error, "Package corrupt or unavailable; no old schema reinterpreted") |> push_navigate(to: "/changes")}
    end
  end

  def handle_params(_, _, socket) do
    rows = case Part3Store.list() do {:ok, list} -> list; _ -> [] end
    {:noreply, socket |> assign(:package, nil) |> assign(:packages, rows) |> assign(:snapshots, Part3Snapshots.identities())}
  end

  @impl true
  def handle_event("create_package", %{"baseline" => a, "proposal" => b}, socket) do
    case Part3Store.create(a, b) do
      {:ok, p} -> {:noreply, push_navigate(socket, to: "/changes/" <> p["id"])}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Package refused: #{inspect(reason)}. Stage exact local source identities in the operator terminal.")}
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
      {:ok, witness} -> {:noreply, edited(socket, witness)}
      {:error, _} -> {:noreply, assign(socket, :editor_error, "Unsupported field, invalid shape or value. No input was changed.")}
    end
  end

  def handle_event("import_json", %{"import" => %{"json" => json}}, socket) when byte_size(json) <= 12_000 do
    with {:ok, value} <- Jason.decode(json),
         {:ok, decoded} <- Adversarial.decode(value),
         {:ok, canonical} <- Adversarial.encode(decoded) do
      {:noreply, edited(socket, canonical)}
    else
      _ -> {:noreply, assign(socket, :editor_error, "Import refused by the same bounded event/state/output codec. Nothing saved.")}
    end
  end

  def handle_event("pin_example", _, socket) do
    case Part3Store.pin(socket.assigns.package["id"], socket.assigns.witness) do
      {:ok, p, _pin} -> {:noreply, socket |> assign(:package, p) |> put_flash(:info, "Saved example; no result inferred, no question answered")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Example not saved: #{inspect(reason)}")}
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
    if socket.assigns.freshness == :ok do
      case Part3AIJobs.request(socket.assigns.package["id"], socket.assigns.draft_human_revision, consent) do
        {:ok, p, _job} -> {:noreply, socket |> assign(:package, p) |> put_flash(:info, "One explicitly authorized model proposal requested. Human answers remain separate.")}
        {:error, reason} -> {:noreply, put_flash(socket, :error, "No send or job: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Source changed; no send")}
    end
  end

  def handle_event("accept_ai_question", %{"job" => job, "proposal" => proposal}, socket) do
    p = socket.assigns.package
    cmd = %{"request_id" => token(), "expected_human_revision" => socket.assigns.draft_human_revision,
      "job_id" => job, "proposal_id" => proposal}
    case Part3Store.accept_question(p["id"], cmd) do
      {:ok, next} -> {:noreply, socket |> assign(:package, next) |> assign(:draft_human_revision, next["human_revision"]) |> put_flash(:info, "Question accepted for human review; it has not been answered")}
      {:error, reason} -> {:noreply, conflict(socket, reason)}
    end
  end

  def handle_event("use_ai_draft", %{"job" => job, "proposal" => proposal}, socket) do
    candidate = with ai when is_map(ai) <- Enum.find(socket.assigns.package["ai_history"], &(&1["id"] == job and &1["status"] == "succeeded")),
      question when is_map(question) <- Enum.find(ai["result"]["proposals"], &(&1["proposal_id"] == proposal)),
      witness when is_map(witness) <- question["witness"],
      {:ok, data} <- Adversarial.decode(witness),
      {:ok, canonical} <- Adversarial.encode(data), do: {:ok, canonical}
    case candidate do
      {:ok, witness} -> {:noreply, edited(socket, witness) |> put_flash(:info, "Model suggestion is an unsaved draft. Explicit pin, replay and human judgment remain separate")}
      _ -> {:noreply, put_flash(socket, :error, "Model question has no supported candidate draft")}
    end
  end

  def handle_event("try_boundary", %{"amount" => raw}, socket) do
    cases = Part3BoundarySearch.cases(socket.assigns.package, socket.assigns.witness)
    case Integer.parse(raw) do
      {amount, ""} ->
        case Enum.find(cases, &(&1["requested_amount"] == amount)) do
          %{"witness" => witness} ->
            {:noreply, edited(socket, witness) |> put_flash(:info,
              "Boundary input drafted. Run isolated comparison explicitly; no general claim inferred.")}
          nil -> {:noreply, put_flash(socket, :error, "Boundary no longer matches this draft")}
        end
      _ -> {:noreply, put_flash(socket, :error, "Invalid boundary amount")}
    end
  end

  def handle_event("run_comparison", _, socket) do
    p = socket.assigns.package
    if socket.assigns.freshness == :ok and is_nil(p["conclusion"]) do
      case Part3Runner.replay(p["id"], socket.assigns.witness) do
        {:ok, _} -> {:noreply, put_flash(socket, :info, "Two isolated local executions requested. Evidence appears when each completes; no run is a proof.")}
        {:error, reason} -> {:noreply, put_flash(socket, :error, "Replay refused: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Read-only package or source drift. No execution launched.")}
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
        {:ok, _} -> {:noreply, put_flash(socket, :info, "Full existing formal gate requested in a separate process; not proof acceptance yet.")}
        {:error, reason} -> {:noreply, put_flash(socket, :error, "Verification refused: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Package is read-only")}
    end
  end

  def handle_event("cancel_attempt", %{"id" => id}, socket) do
    case Part3Runner.cancel(socket.assigns.package["id"], id) do
      {:ok, _} -> {:noreply, put_flash(socket, :info, "Attempt cancelled; interrupted evidence remains visible")}
      _ -> {:noreply, put_flash(socket, :error, "Attempt already terminal or not owned by this review")}
    end
  end

  def handle_event("record_finding", %{"finding" => form}, socket) do
    p = socket.assigns.package
    cmd = %{
      "request_id" => token(), "expected_human_revision" => socket.assigns.draft_human_revision,
      "lens" => form["lens"], "status" => form["status"], "scope" => form["scope"],
      "rationale" => form["rationale"], "change_ids" => Map.get(form, "change_ids", []),
      "evidence_ids" => Map.get(form, "evidence_ids", []),
      "presentation" => socket.assigns.mode, "revealed_before_answer" => socket.assigns.revealed
    }
    case Part3Store.finding(p["id"], cmd) do
      {:ok, updated} -> {:noreply, socket |> assign(:package, updated) |> assign(:draft_human_revision, updated["human_revision"]) |> put_flash(:info, "Scoped human finding recorded. Prior findings retained.")}
      {:error, reason} -> {:noreply, conflict(socket, reason)}
    end
  end

  def handle_event("conclude", %{"conclusion" => form}, socket) do
    p = socket.assigns.package
    cmd = %{"request_id" => token(), "expected_human_revision" => socket.assigns.draft_human_revision,
      "outcome" => form["outcome"], "scope" => form["scope"], "rationale" => form["rationale"],
      "evidence_ids" => Map.get(form, "evidence_ids", []), "confirmed" => true}
    case Part3Store.conclude(p["id"], cmd) do
      {:ok, updated} -> {:noreply, socket |> assign(:package, updated) |> assign(:draft_human_revision, updated["human_revision"]) |> put_flash(:info, "Human conclusion recorded with scope; not formal acceptance")}
      {:error, reason} -> {:noreply, conflict(socket, reason)}
    end
  end

  @impl true
  def handle_info({:part3_updated, id}, socket) do
    if socket.assigns.package && socket.assigns.package["id"] == id do
      case Part3Store.get(id) do
        {:ok, p, freshness} -> {:noreply, socket |> assign(:package, p) |> assign(:freshness, freshness)}
        _ -> {:noreply, put_flash(socket, :error, "Saved package no longer readable")}
      end
    else
      {:noreply, socket}
    end
  end

  defp conflict(socket, reason) do
    put_flash(socket, :error, "Not saved (#{inspect(reason)}). Another tab or job may have changed the revision; your on-screen draft is unchanged. Check the saved history before submitting again.")
  end

  defp seed(socket, id) do
    case Adversarial.seed(id) do
      {:ok, witness} -> edited(socket, witness)
      _ -> put_flash(socket, :error, "Unknown starting scenario")
    end
  end

  defp edited(socket, witness) do
    socket |> assign(:witness, witness) |> assign(:raw_input, Jason.encode!(witness, pretty: true))
      |> assign(:editor_error, nil)
      |> assign(:revealed, socket.assigns.mode == "expert")
  end

  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

  defp matching_replays(package, witness) do
    digest = Canonical.digest(witness)
    matches = Enum.filter(package["replay_attempts"], &(&1["input_digest"] == digest and &1["status"] == "succeeded"))
    a = Enum.reverse(matches) |> Enum.find(&(&1["snapshot_id"] == package["baseline"]["snapshot_id"]))
    b = Enum.reverse(matches) |> Enum.find(&(&1["snapshot_id"] == package["proposal"]["snapshot_id"]))
    if a && b, do: {a["result"], b["result"]}, else: nil
  end

  attr :section, :string, required: true
  attr :state, :map, required: true
  attr :editable, :boolean, default: true
  defp state_controls(assigns) do
    ~H"""
    <div class="part3-state">
      <div class="part3-fields">
        <div :for={field <- ~w(amount_limit hold_limit used_amount used_holds)}>
          <label for={"#{@section}-#{field}"}>{String.replace(field, "_", " ")}</label>
          <input id={"#{@section}-#{field}"} type="number" min="0" max="1000000" value={@state[field]}
            phx-change="structured_change" phx-value-action="state" phx-value-section={@section}
            phx-value-field={field} name="value" disabled={!@editable} />
        </div>
      </div>
      <p class="muted">Entry identities and holding statuses are deliberately editable. Used totals are independent.</p>
      <div :for={{entry, index} <- Enum.with_index(@state["entries"])} class="part3-entry">
        <div :for={field <- ~w(key amount)}>
          <label for={"#{@section}-#{index}-#{field}"}>{field}</label>
          <input id={"#{@section}-#{index}-#{field}"} name="value" type="number" min="0" max="1000000"
            value={entry[field]} phx-change="structured_change" phx-value-action="entry" phx-value-section={@section}
            phx-value-field={field} phx-value-index={index} disabled={!@editable} />
        </div>
        <div>
          <label for={"#{@section}-#{index}-status"}>Status</label>
          <select id={"#{@section}-#{index}-status"} name="value" phx-change="structured_change"
            phx-value-action="entry" phx-value-section={@section} phx-value-field="status"
            phx-value-index={index} disabled={!@editable}>
            <option :for={status <- TermCodec.statuses()} value={status} selected={status == entry["status"]}>{status}</option>
          </select>
        </div>
        <button type="button" phx-click="structured_change" phx-value-action="remove_entry"
          phx-value-section={@section} phx-value-index={index} disabled={!@editable}>Remove entry</button>
      </div>
      <div class="part3-actions">
        <button type="button" phx-click="structured_change" phx-value-action="add_entry" phx-value-section={@section} disabled={!@editable}>Add entry</button>
        <button type="button" phx-click="structured_change" phx-value-action="recalculate" phx-value-section={@section} disabled={!@editable}>Recalculate used totals (explicit)</button>
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
      <div>
        <label for={"#{@section}-type"}>Event</label>
        <select id={"#{@section}-type"} name="value" phx-change="structured_change" phx-value-action="event"
          phx-value-section={@section} phx-value-field="type" disabled={!@editable}>
          <option :for={type <- ~w(request dispatch timeout void)} value={type} selected={@event && @event["type"] == type}>{type}</option>
        </select>
      </div>
      <div :for={field <- ~w(key amount)} :if={@event && (field == "key" || @event["type"] == "request")}>
        <label for={"#{@section}-#{field}"}>{field}</label>
        <input id={"#{@section}-#{field}"} name="value" type="number" min="0" max="1000000"
          value={@event[field]} phx-change="structured_change" phx-value-action="event"
          phx-value-section={@section} phx-value-field={field} disabled={!@editable} />
      </div>
      <button :if={@section == "follow_on"} type="button" phx-click="structured_change"
        phx-value-action="no_follow_on" disabled={!@editable}>No follow-on event</button>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :triage, if(assigns.package, do: Part3Diagnostics.triage(assigns.package), else: []))
    assigns = assign(assigns, :replays, if(assigns.package && assigns.witness, do: matching_replays(assigns.package, assigns.witness), else: nil))
    assigns = assign(assigns, :editable, assigns.package && assigns.freshness == :ok && is_nil(assigns.package["conclusion"]))
    ~H"""
    <Layouts.app flash={@flash}>
      <%= if @package == nil do %>
        <section class="part3-home">
          <p class="eyebrow">Versioned review / local snapshots</p>
          <h1>Review a proposed change against a fixed baseline.</h1>
          <p>The governing payment policy is independent of both revisions. Source edits are triggers for review, not demonstrated semantic weakening. Start a separate <.link navigate="/workbench">single-version scenario</.link> if you only need a what-if.</p>
          <h2>Identify two operator-staged local snapshots</h2>
          <p class="muted">A snapshot is staged from a trusted local terminal by the documented script. Names or branches are not identities. No uploaded executable source or automatic dependency fetch is accepted.</p>
          <form phx-submit="create_package" id="create-change-package" class="part3-create">
            <div><label for="baseline-id">Baseline content identity</label>
              <select id="baseline-id" name="baseline" required><option value="">Select baseline</option><option :for={id <- @snapshots} value={id}>{String.slice(id, 0, 20)}</option></select></div>
            <div><label for="proposal-id">Proposal content identity</label>
              <select id="proposal-id" name="proposal" required><option value="">Select proposal</option><option :for={id <- @snapshots} value={id}>{String.slice(id, 0, 20)}</option></select></div>
            <button class="primary" type="submit" disabled={length(@snapshots) < 2}>Create separate versioned review</button>
          </form>
          <h2>Saved change reviews</h2>
          <ul class="review-list" id="part3-package-list">
            <li :for={p <- @packages}><.link navigate={"/changes/" <> p["id"]}>{String.slice(p["baseline_id"], 0, 12)} → {String.slice(p["proposal_id"], 0, 12)}</.link>
              <span>Human revision {p["human_revision"]} · {p["updated_at"]}</span></li>
          </ul>
        </section>
      <% else %>
        <header class="part3-header">
          <p class="eyebrow">Identified proposed change / local operator trust</p>
          <h1>What promise changed?</h1>
          <p><b>Baseline</b> <code>{@package["baseline"]["snapshot_id"]}</code><small> {if @package["baseline"]["dirty"], do: "dirty captured bytes", else: "committed clean bytes"}</small></p>
          <p><b>Proposal</b> <code>{@package["proposal"]["snapshot_id"]}</code><small> {if @package["proposal"]["dirty"], do: "dirty captured bytes", else: "committed clean bytes"}</small></p>
          <nav aria-label="Review navigation"><.link navigate="/changes">All change reviews</.link> · <.link navigate="/workbench">Single-version review</.link></nav>
          <p :if={@freshness != :ok} role="alert" class="notice-alert">Source or toolchain drift: this historical package is read-only. An old answer is not rebound to new bytes.</p>
          <p :if={@package["conclusion"]} class="notice-alert">Human conclusion recorded: {@package["conclusion"]["outcome"]}. Read-only; not formal acceptance.</p>
          <div class="part3-presentation" aria-label="Presentation mode">
            <button type="button" phx-click="presentation" phx-value-mode="expert" aria-pressed={@mode == "expert"}>Expert: evidence first</button>
            <button type="button" phx-click="presentation" phx-value-mode="learning" aria-pressed={@mode == "learning"}>Learning: predict first</button>
          </div>
        </header>
        <main class="part3-main">
          <section class="part3-primary" aria-label="Decision and evidence">
            <h2>Relevant source changes <small>{length(@package["source_changes"])} paths</small></h2>
            <p :if={@package["source_changes"] == []}>No source differences in these identified manifests. This does not prove semantic equivalence.</p>
            <ol class="part3-changes" id="part3-source-delta">
              <li :for={change <- @package["source_changes"]}>
                <details>
                  <summary><code>{change["path"]}</code> · {String.replace(change["kind"], "_", " ")} · structural edit only</summary>
                  <p :if={change["claim"]["analysis"] == "supported_structural_ast"} class="muted">Condition changed: {to_string(change["claim"]["changed"]["conditions"])}; promised result changed: {to_string(change["claim"]["changed"]["promises"])}. No general relation asserted.</p>
                  <div class="part3-sources"><div><h3>Baseline</h3><pre>{change["baseline_excerpt"]}</pre></div><div><h3>Proposal</h3><pre>{change["proposal_excerpt"]}</pre></div></div>
                  <small>Source hashes: {change["baseline_sha256"] || "absent"} / {change["proposal_sha256"] || "absent"}. {change["claim"]["analysis"]}</small>
                </details>
              </li>
            </ol>
            <section class="part3-comparison" id="part3-comparison">
              <h2>Concrete example and isolated execution</h2>
              <p>Both runs require the same valid starting ledger and typed candidate. A wrong but structurally representable outcome is allowed; incorrect accounting is not silently repaired.</p>
              <div class="part3-actions"><button :for={seed <- Adversarial.seeds()} type="button" phx-click="starting_scenario" phx-value-seed={seed}>{seed}</button></div>
              <div :if={@witness} class="part3-sides">
                <div><b>Input/event</b><p>{@witness["event"]["type"]} / key {@witness["event"]["key"]}</p><p>Amount limit {@witness["before"]["amount_limit"]}, in use {@witness["before"]["used_amount"]}</p></div>
                <div><b>Proposed outcome to challenge</b><p>Result {@witness["output"]["result"]}</p><p>Used amount {@witness["output"]["after"]["used_amount"]}, holds {@witness["output"]["after"]["used_holds"]}</p></div>
              </div>
              <%= if @mode == "learning" && !@revealed do %>
                <p>Predict whether an exact-fit input belongs to each version's promise, and whether the candidate should be permitted. Predictions are not secretly collected.</p>
                <button type="button" phx-click="reveal" id="part3-reveal">Show computed evidence</button>
              <% else %>
                <%= if @replays do %>
                  <div class="part3-sides" id="part3-replay-result">
                    <div><h3>Baseline actual</h3><pre>{Jason.encode!(elem(@replays, 0)["evaluation"]["actual"], pretty: true)}</pre></div>
                    <div><h3>Proposal actual</h3><pre>{Jason.encode!(elem(@replays, 1)["evaluation"]["actual"], pretty: true)}</pre></div>
                  </div>
                  <p class="muted">Pointwise observations for this exact draft only. A contract-only permitted alternative does not mean the implementation produced it.</p>
                <% else %>
                  <p id="part3-missing-replay" class="muted">No completed pair of isolated executions for this exact draft. Source comparison remains structural; replay is NOT RUN or pending.</p>
                <% end %>
                <ul id="part3-evidence-list">
                  <li :for={e <- @package["evidence"]}><b>{String.replace(e["kind"], "_", " ")}</b> · {e["level"]}<p>{e["note"]}</p><small>{e["id"]} · method {e["method"]} · one input</small></li>
                </ul>
              <% end %>
              <div class="part3-actions">
                <button type="button" phx-click="pin_example" id="part3-pin" disabled={!@editable}>Save/pin this draft (no execution)</button>
                <button type="button" phx-click="run_comparison" id="run-isolated-replay" class="primary" disabled={!@editable}>Run both identified versions locally</button>
              </div>
              <details id="part3-pins"><summary>Saved example drafts · {length(@package["pinned_examples"])}</summary>
                <ul><li :for={pin <- @package["pinned_examples"]}><button type="button" phx-click="load_pinned" phx-value-id={pin["id"]}>Open example {String.slice(pin["input_digest"], 0, 16)}</button> · saved {pin["pinned_at"]}</li></ul>
              </details>
              <h3>Execution attempts and failures</h3>
              <ul id="part3-replay-attempts">
                <li :for={a <- @package["replay_attempts"]}>{String.slice(a["snapshot_id"], 0, 12)} · {a["status"]} · {a["diagnostics"]} · {a["scope"]}
                  <button :if={a["status"] in ~w(queued running)} type="button" phx-click="cancel_attempt" phx-value-id={a["id"]}>Cancel</button></li>
              </ul>
            </section>
            <section id="part3-decision">
              <h2>Human finding beside the evidence</h2>
              <p :if={@draft_human_revision != @package["human_revision"]} role="alert" class="notice-alert">Another tab has recorded a human decision. Your form is not silently rebound. Inspect the saved answer, then deliberately <button type="button" phx-click="refresh_human_revision">use the current human revision</button> to submit.</p>
              <p>Each lens remains reviewable even with no automatic trigger. An absent trigger is not evidence that the requirement is inapplicable.</p>
              <dl :for={lens <- @triage} class="part3-lens">
                <dt><b>{String.replace(lens["lens"], "_", " ")}</b> · {lens["status"]}</dt>
                <dd>{lens["question"]}<small> {length(lens["changes"])} relevant source edits · {lens["triage"]}</small></dd>
                <dd :if={lens["latest"]}><b>Last human reason:</b> {lens["latest"]["rationale"]} · revealed before answer: {to_string(lens["latest"]["revealed_before_answer"])}</dd>
              </dl>
              <form id="part3-finding" phx-submit="record_finding" class="part3-judgment">
                <label for="part3-lens">Concern to address</label>
                <select id="part3-lens" name="finding[lens]" required><option :for={l <- @triage} value={l["lens"]}>{String.replace(l["lens"], "_", " ")}</option></select>
                <label for="part3-finding-status">Finding status</label>
                <select id="part3-finding-status" name="finding[status]"><option value="unresolved">Unresolved</option><option value="addressed">Addressed in stated scope</option><option value="not_applicable">Not applicable (give reason)</option></select>
                <label for="part3-finding-scope">Scope actually reviewed</label><input id="part3-finding-scope" name="finding[scope]" required maxlength="600" />
                <label for="part3-finding-rationale">Policy-based rationale / missing evidence</label><textarea id="part3-finding-rationale" name="finding[rationale]" required minlength="5" maxlength="1200" rows="3"></textarea>
                <details><summary>Attach changed source and computed evidence IDs</summary>
                  <label :for={c <- @package["source_changes"]}><input type="checkbox" name="finding[change_ids][]" value={c["id"]} />{c["path"]}</label>
                  <label :for={e <- @package["evidence"]}><input type="checkbox" name="finding[evidence_ids][]" value={e["id"]} />{e["kind"]} / {e["id"]}</label>
                </details>
                <button type="submit" disabled={!@editable}>Record human finding</button>
              </form>
              <details><summary>Prior human findings and revision history</summary>
                <ol><li :for={f <- @package["human_findings"]}><b>{f["lens"]}: {f["status"]}</b> · revision {f["human_revision"]}<p>{f["rationale"]}</p></li></ol>
              </details>
              <details id="part3-accepted-questions"><summary>Deliberately accepted model questions (not answers)</summary>
                <ul><li :for={q <- @package["accepted_questions"]}><b>{q["kind"]}</b> · {q["question"]}<small> accepted human revision {q["human_revision"]}</small></li></ul>
              </details>
              <h3>Separate human conclusion</h3>
              <form id="part3-conclude" phx-submit="conclude" class="part3-judgment">
                <label for="part3-outcome">Conclusion</label><select id="part3-outcome" name="conclusion[outcome]"><option value="needs_policy_or_evidence">Needs policy or evidence</option><option value="needs_design_change">Needs design change</option><option value="meets_intent_in_reviewed_scope">Meets intent only in reviewed scope</option></select>
                <label for="part3-scope">Reviewed scope</label><input id="part3-scope" name="conclusion[scope]" required maxlength="600" />
                <label for="part3-rationale">Reason</label><textarea id="part3-rationale" name="conclusion[rationale]" required minlength="5" maxlength="1200" rows="3"></textarea>
                <details><summary>Attach computed evidence</summary><label :for={e <- @package["evidence"]}><input type="checkbox" name="conclusion[evidence_ids][]" value={e["id"]} />{e["kind"]}</label></details>
                <button type="submit" id="part3-finish" disabled={!@editable}>Confirm my conclusion (not proof acceptance)</button>
              </form>
            </section>
          </section>
          <aside class="part3-context" aria-label="Edit example and inspect proof details">
            <details id="part3-structured-editor">
              <summary><b>Edit the example</b> · structured controls</summary>
              <details id="part3-boundary-search"><summary>Targeted request-amount boundaries</summary>
                <p>For affected rules and helpers, try below, at, and above the starting ledger's remaining amount limit. Up to three supported examples; no search-exhaustion or equivalence claim.</p>
                <div class="part3-actions">
                  <button :for={item <- Part3BoundarySearch.cases(@package, @witness)}
                    type="button" phx-click="try_boundary" phx-value-amount={item["requested_amount"]}
                    disabled={!@editable}>{item["label"]} · amount {item["requested_amount"]}</button>
                </div>
              </details>
              <p :if={@editor_error} class="notice-alert" role="alert">{@editor_error}</p>
              <%= if @witness do %>
                <h3>Valid starting ledger required for execution</h3>
                <.state_controls section="before" state={@witness["before"]} editable={@editable} />
                <h3>Event</h3><.event_controls section="event" event={@witness["event"]} editable={@editable} />
                <h3>Candidate after-state · counters may be intentionally wrong</h3>
                <.state_controls section="candidate" state={@witness["output"]["after"]} editable={@editable} />
                <label for="part3-result">Candidate result</label>
                <select id="part3-result" name="value" phx-change="structured_change" phx-value-action="result" disabled={!@editable}>
                  <option :for={r <- TermCodec.results()} value={r} selected={r == @witness["output"]["result"]}>{r}</option>
                </select>
                <h3>Requested external effects (not performed)</h3>
                <div :for={{effect, index} <- Enum.with_index(@witness["output"]["effects"])} class="part3-fields">
                  <div><label for={"effect-type-#{index}"}>Effect type</label>
                    <select id={"effect-type-#{index}"} name="value" phx-change="structured_change" phx-value-action="effect" phx-value-field="type" phx-value-index={index} disabled={!@editable}>
                      <option :for={type <- ~w(void authorize)} value={type} selected={effect["type"] == type}>{type}</option></select></div>
                  <div :for={field <- ~w(key amount)} :if={field == "key" || effect["type"] == "authorize"}>
                    <label for={"effect-#{index}-#{field}"}>{field}</label><input id={"effect-#{index}-#{field}"} name="value" type="number" min="0" max="1000000"
                      value={effect[field]} phx-change="structured_change" phx-value-action="effect" phx-value-field={field} phx-value-index={index} disabled={!@editable} />
                  </div>
                  <button type="button" phx-click="structured_change" phx-value-action="remove_effect" phx-value-index={index} disabled={!@editable}>Remove effect</button>
                </div>
                <button type="button" phx-click="structured_change" phx-value-action="add_effect" disabled={!@editable}>Add effect</button>
                <h3>Optional next event</h3><.event_controls section="follow_on" event={@witness["follow_on"]} editable={@editable} />
                <details><summary>Advanced JSON · same strict codec for import</summary>
                  <pre id="part3-export-json">{Jason.encode!(@witness, pretty: true)}</pre>
                  <form phx-submit="import_json" id="part3-import"><label for="part3-raw">Import edited example</label><textarea id="part3-raw" name="import[json]" rows="8" maxlength="12000">{@raw_input}</textarea><button type="submit" disabled={!@editable}>Validate and load as unsaved draft</button></form>
                </details>
              <% end %>
            </details>
            <details id="part3-proof"><summary><b>Proof artifacts and provenance</b> · inspect separately</summary>
              <p>Formal acceptance is derived only by the repository's full required-scope source-matching report validator. An axiom name or no `sorry` does not establish acceptance.</p>
              <button type="button" phx-click="inspect_proof" id="part3-inspect-proof">Inspect registered source and checked artifacts</button>
              <%= case @proof_inspection do %>
                <% {:ok, inspected} -> %>
                  <p id="part3-proof-inspection">Registered obligations: {inspected["catalog_count"]}. Report {inspected["report_status"]}; acceptance {inspected["formal_acceptance"]}.</p>
                  <details :for={item <- inspected["sources"]} class="part3-proof-law">
                    <summary>{item["slug"]} · {item["purpose"]} · {item["artifact_scope"]}</summary>
                    <p>Original claim/source: {item["source"]["path"]} / {item["source"]["sha256"]}</p>
                    <pre>{item["source"]["excerpt"] || "Source is missing or stale"}</pre>
                    <p>Translated statement: {inspect(item["translated_statement"])}</p>
                    <p>Recorded proof dependencies: {inspect(item["proof_dependencies"])}</p>
                    <p>Checker evidence: {inspect(item["checker_result"])}</p>
                    <p>Exports: {inspect(item["exports"])}</p>
                  </details>
                <% {:error, reason} -> %>
                  <p role="alert">Proof inspection unavailable: {inspect(reason)}</p>
                <% _ -> %>
                  <p>Open the inspector to read exact registered source and any matching artifacts. Missing translation, exports or dependencies stay missing.</p>
              <% end %>
              <button type="button" phx-click="verify_full" id="part3-run-formal" disabled={!@editable}>Request full existing verification gate</button>
              <ul id="part3-verification-attempts"><li :for={a <- @package["verification_attempts"]}><b>{a["kind"]} · {a["status"]}</b> · {a["diagnostics"]}
                <small>{a["producer"]} / {a["scope"]} / {a["snapshot_id"]}</small>
                <small :for={artifact <- a["artifacts"]}>{artifact["path"]} / {artifact["sha256"]}</small>
                <button :if={a["status"] in ~w(queued running)} type="button" phx-click="cancel_attempt" phx-value-id={a["id"]}>Cancel</button></li></ul>
              <p :if={@package["verification_attempts"] == []}>No proposal formal verification supplied or run. Elaboration, export, independent checkers and full acceptance: NOT RUN.</p>
              <details><summary>Lean, translation, dependency and inventory source changes</summary>
                <p :for={c <- @package["source_changes"]} :if={c["kind"] in ~w(lean_declaration_or_dependency translation_or_elaboration obligation_or_inventory)}>{c["path"]} · source digest {c["proposal_sha256"]} · proof/dependency meaning requires human inspection</p>
                <p>Translated theorems, proof dependencies and checker exports are not fabricated when artifacts are absent.</p>
              </details>
            </details>
            <details id="part3-policy"><summary><b>Governing policy and review limits</b></summary>
              <p :for={policy <- @package["policy_anchors"]}>{policy["authority"]}: {policy["path"]} ({policy["passage"]}) · digest <code>{policy["sha256"]}</code></p>
              <p>Process separation prevents module mixing, not malicious code. Only locally staged operator-trusted source can execute. A changed code representation needs explicit correspondence; unsupported general implications remain unresolved.</p>
            </details>
            <details id="part3-ai"><summary><b>Optional AI proposer</b> · consent required for every send</summary>
              <p>Only bounded policy and identified source excerpts plus typed evidence summaries are sent if you authorize this particular request. Your answers, conclusions, private benchmarks, hidden rubrics and credentials are excluded. A model question is not an independent finding.</p>
              <p id="part3-ai-no-consent">Consent defaults to off on every page load. No auto resend on reload or reconnect. The existing Inference ASM/Codex model is unchanged; unavailable credentials mean no send.</p>
              <form phx-submit="request_ai" id="part3-ai-request" class="part3-judgment">
                <label for="part3-ai-consent"><input id="part3-ai-consent" type="checkbox" name="ai[consent]" value="true" required />Authorize one package-source send now</label>
                <button type="submit" disabled={!@editable}>Request model questions (optional)</button>
              </form>
              <ul id="part3-ai-jobs"><li :for={job <- @package["ai_history"]}>
                <p>Model proposal · {job["status"]} · requested under human revision {job["human_revision_at_request"]} · {job["error"]}</p>
                <%= if job["result"] do %>
                  <div :for={proposal <- job["result"]["proposals"]} class="part3-model-question">
                    <b>{proposal["kind"]}</b><p>{proposal["question"]}</p><p class="muted">{proposal["rationale"]}</p>
                    <div class="part3-actions">
                      <button type="button" phx-click="use_ai_draft" phx-value-job={job["id"]} phx-value-proposal={proposal["proposal_id"]} disabled={!@editable || is_nil(proposal["witness"]) || job["status"] != "succeeded"}>Use suggested case as unsaved draft</button>
                      <button type="button" phx-click="accept_ai_question" phx-value-job={job["id"]} phx-value-proposal={proposal["proposal_id"]} disabled={!@editable || job["status"] != "succeeded"}>Accept question only</button>
                    </div>
                  </div>
                <% end %>
              </li></ul>
            </details>
          </aside>
        </main>
      <% end %>
    </Layouts.app>
    """
  end
end
