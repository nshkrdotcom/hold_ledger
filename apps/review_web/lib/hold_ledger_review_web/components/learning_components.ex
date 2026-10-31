defmodule HoldLedgerReviewWeb.LearningComponents do
  @moduledoc "Shared navigation and source-grounded illustrations for the learning pages."
  use HoldLedgerReviewWeb, :html
  alias HoldLedgerReviewWeb.Education

  @chapters [
    {:start, "01", "Payment walkthrough", "/start"},
    {:system, "02", "System guide", "/system"},
    {:guarantees, "03", "Payment requirements", "/guarantees"},
    {:translation, "04", "Elixir to Lean", "/translation"},
    {:proofs, "05", "Read a claim", "/proofs"}
  ]

  attr :current, :atom, required: true

  def chapter_nav(assigns) do
    assigns = assign(assigns, :chapters, @chapters)

    ~H"""
    <nav id="learning-chapters" class="learning-chapters" aria-label="Learning chapters">
      <span>Learn by following one hold</span>
      <ol>
        <li :for={{action, number, label, path} <- @chapters}>
          <a href={path} aria-current={if(@current == action, do: "page")}>
            <span aria-hidden="true">{number}</span>{label}
          </a>
        </li>
      </ol>
    </nav>
    """
  end

  def concept_intro(assigns) do
    ~H"""
    <section class="learning-concepts" aria-label="Three ideas behind the app">
      <div>
        <h2>Formal verification</h2>
        <p>Use mathematical proofs to check precisely stated properties of code.</p>
      </div>
      <div>
        <h2><button type="button" class="edu-term-button" data-edu-term="lynx">Lynx</button></h2>
        <p>Translates supported Elixir code and laws into Lean.</p>
      </div>
      <div>
        <h2><button type="button" class="edu-term-button" data-edu-term="lean">Lean</button></h2>
        <p>Checks a supplied proof against its theorem and assumptions.</p>
      </div>
    </section>
    """
  end

  def vocabulary_ladder(assigns) do
    ~H"""
    <dl class="learning-vocabulary" aria-label="From requirement to proof">
      <div><dt><a href="/guarantees">Requirement</a></dt><dd>The behavior we need</dd></div>
      <div><dt><a href="/atlas">Claim</a></dt><dd>A precise statement about it</dd></div>
      <div><dt><a href="/translation">Lean theorem</a></dt><dd>The statement Lean receives</dd></div>
      <div><dt><a href="/assurance">Proof and evidence</a></dt><dd>The argument and the checks run</dd></div>
    </dl>
    """
  end

  attr :claims, :list, required: true
  attr :families, :list, required: true
  attr :requirements, :list, required: true
  attr :selected, :string, default: "all"

  def claim_map(assigns) do
    requirement = Enum.find(assigns.requirements, &(&1.id == assigns.selected))

    assigns =
      assign(assigns,
        requirement: requirement,
        inventory: Education.inventory(assigns.claims),
        related_count:
          if(requirement,
            do: Enum.count(assigns.claims, &(&1["slug"] in requirement.slugs)),
            else: length(assigns.claims)
          )
      )

    ~H"""
    <section id="edu-claim-map" class="claim-map" aria-labelledby="claim-map-title">
      <header class="claim-map-heading">
        <div>
          <p class="edu-eyebrow">The claims in context</p>
          <h2 id="claim-map-title">From a payment requirement to a precise claim.</h2>
          <p>Choose a requirement to highlight related claims. Open any claim to read its example and source.</p>
        </div>
        <a href="/atlas#edu-atlas-browser" class="map-browse-link">Search Claim Atlas <span aria-hidden="true">↗</span></a>
      </header>
      <div class="map-requirements" role="group" aria-label="Highlight claims by requirement">
        <button
          type="button"
          phx-click="map_requirement"
          phx-value-id="all"
          aria-pressed={to_string(@selected == "all")}
          aria-controls="claim-map-families"
        >All requirements</button>
        <button
          :for={requirement <- @requirements}
          type="button"
          phx-click="map_requirement"
          phx-value-id={requirement.id}
          aria-pressed={to_string(@selected == requirement.id)}
          aria-controls="claim-map-families"
        ><span aria-hidden="true">{requirement.number}</span>{requirement.title}</button>
      </div>
      <div class="map-selection" id="claim-map-selection" role="status" aria-live="polite">
        <%= if @requirement do %>
          <p><strong>{@requirement.title}.</strong> {@requirement.nutshell}</p>
          <span>{@related_count} claim groups in this reading list</span>
          <a href={"/guarantees?requirement=" <> @requirement.id}>Read this requirement →</a>
        <% else %>
          <p><strong>{@inventory.total} registered claim groups</strong> in {length(@families)} families. Each family answers a different question.</p>
          <span>{@inventory.elixir} Elixir law groups · {@inventory.lean} Lean-only groups</span>
        <% end %>
      </div>
      <div class="map-families" id="claim-map-families">
        <section :for={family <- @families} class="map-family" data-map-family={family.id}>
          <header>
            <span class="map-family-number">{family.number}</span>
            <h3><a href={"/atlas?family=" <> URI.encode_www_form(family.id)}>{family.id}</a></h3>
            <span class="map-family-count" aria-label="Registered groups in this family">
              {length(Education.by_family(@claims, family.id))}
            </span>
          </header>
          <p>{family.question}</p>
          <ul class="map-claims">
            <li :for={claim <- Education.by_family(@claims, family.id)}>
              <a
                href={"/atlas/" <> claim["slug"]}
                data-map-claim={claim["slug"]}
                data-related={to_string(is_nil(@requirement) or claim["slug"] in @requirement.slugs)}
                class={["map-claim", claim["kind"] == "native_lean" && "map-claim-lean"]}
                aria-label={claim["id"] <> ": " <> claim["title"] <> " · " <> kind_label(claim) <> relationship_label(@requirement, claim)}
              >
                <span class="map-kind" aria-hidden="true">{if(claim["kind"] == "native_lean", do: "L", else: "E")}</span>
                <span>{claim["id"]}</span>
                <span
                  :if={@requirement && claim["slug"] in @requirement.slugs}
                  class="map-related-mark"
                  aria-hidden="true"
                >✓</span>
              </a>
            </li>
          </ul>
        </section>
      </div>
      <footer class="map-caption">
        <p>A reading map of related claims. It does not show proof dependencies or establish that every requirement is covered.</p>
        <div class="map-key"><span><b class="map-kind">E</b> Elixir law</span><span><b class="map-kind map-kind-lean">L</b> Lean-only</span></div>
      </footer>
    </section>
    """
  end

  defp kind_label(%{"kind" => "native_lean"}), do: "Lean-only claim"
  defp kind_label(_), do: "Elixir law"

  defp relationship_label(nil, _claim), do: ""

  defp relationship_label(requirement, claim) do
    if claim["slug"] in requirement.slugs,
      do: " · In the selected requirement's reading list",
      else: " · Outside the selected requirement's reading list"
  end

  attr :moment, :map, required: true
  attr :possibility, :string, required: true

  def uncertainty_view(assigns) do
    ~H"""
    <section id="edu-uncertainty" class="uncertainty-view" aria-labelledby="uncertainty-title">
      <header>
        <p class="edu-eyebrow">One observation, two possible explanations</p>
        <h2 id="uncertainty-title">What happened at the processor?</h2>
        <p>The ledger cannot tell from a missing reply. Explore the possibilities while keeping the local state in view.</p>
      </header>
      <div class="uncertainty-pair">
        <section class="uncertainty-local">
          <span class="uncertainty-label">What the ledger knows</span>
          <h3>The reply is missing.</h3>
          <dl>
            <div><dt>Amount still held</dt><dd>{@moment.ledger["used_amount"]}¢</dd></div>
            <div><dt>Slots still used</dt><dd>{@moment.ledger["used_holds"]}</dd></div>
          </dl>
          <p>Hold 11 remains <button type="button" class="edu-term-button" data-edu-term="unknown">unknown</button> in either case.</p>
        </section>
        <section class="uncertainty-remote">
          <span class="uncertainty-label">Possible outcomes · illustration</span>
          <div class="uncertainty-choices" role="group" aria-label="Explore a possible processor outcome">
            <button type="button" phx-click="processor_possibility" phx-value-id="approved" data-possibility="approved" aria-pressed={to_string(@possibility == "approved")} aria-controls="edu-processor-possibility">Approved; reply lost</button>
            <button type="button" phx-click="processor_possibility" phx-value-id="undelivered" data-possibility="undelivered" aria-pressed={to_string(@possibility == "undelivered")} aria-controls="edu-processor-possibility">Request never arrived</button>
          </div>
          <div id="edu-processor-possibility" aria-live="polite">
            <%= if @possibility == "approved" do %>
              <h3>The authorization may be live.</h3>
              <p>The processor approved 100¢, but the reply was lost. Releasing the local hold could let another request use capacity that is already committed.</p>
            <% else %>
              <h3>The request may never have arrived.</h3>
              <p>The authorization request never reached the processor. The ledger still has no reply, so it cannot safely distinguish this case from an approval with a lost reply.</p>
            <% end %>
          </div>
        </section>
      </div>
      <p class="uncertainty-takeaway"><strong>Keep the capacity held.</strong> Choosing a possibility changes this illustration only. The ledger result above stays the same.</p>
      <a href="/atlas/po_b2">Read the unresolved-hold claim →</a>
    </section>
    """
  end

  attr :focus, :string, required: true

  def translation_guide(assigns) do
    ~H"""
    <section id="translation-focus" class="translation-focus" aria-labelledby="translation-focus-title">
      <div>
        <p class="edu-eyebrow">Read one part at a time</p>
        <h2 id="translation-focus-title">What does the law ask Lean to establish?</h2>
        <div class="translation-focus-controls" role="group" aria-label="Choose a part of the law">
          <button type="button" phx-click="translation_focus" phx-value-id="requires" aria-pressed={to_string(@focus == "requires")} aria-controls="translation-focus-explanation">Inputs · requires</button>
          <button type="button" phx-click="translation_focus" phx-value-id="expects" aria-pressed={to_string(@focus == "expects")} aria-controls="translation-focus-explanation">Output · expects</button>
          <button type="button" phx-click="translation_focus" phx-value-id="proof" aria-pressed={to_string(@focus == "proof")} aria-controls="translation-focus-explanation">Supplied proof</button>
        </div>
      </div>
      <div id="translation-focus-explanation" aria-live="polite">
        <%= case @focus do %>
          <% "requires" -> %>
            <h3>Which inputs receive the promise?</h3>
            <p><code>Spec.request_eligible?</code> checks the valid state, new key, positive amount and available capacity. Its <code>&lt;=</code> comparison includes an exact fit.</p>
            <a href="#translation-implementation" data-reveal-source>Read the eligibility predicate →</a>
          <% "expects" -> %>
            <h3>What must the code return?</h3>
            <p>The claim requires the exact admitted output: updated counters, a new reserved entry and no effects. It also requires agreement with the independent Spec.</p>
            <a href="#translation-expects" data-reveal-source>Read the required output →</a>
          <% "proof" -> %>
            <h3>How is that statement justified?</h3>
            <p>The law supplies Lean proof text that invokes the repository's PO-A2 theorem. The theorem uses the generated input and output conditions.</p>
            <a href="#translation-proof" data-reveal-source>Read the supplied proof →</a>
        <% end %>
      </div>
    </section>
    """
  end
end
