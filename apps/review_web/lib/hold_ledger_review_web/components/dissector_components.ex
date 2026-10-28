defmodule HoldLedgerReviewWeb.DissectorComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html

  attr :case, :map, default: nil
  attr :reading, :map, required: true
  attr :basis, :string, default: "candidate"
  attr :helper, :map, default: nil
  attr :binding_index, :integer, default: 0
  attr :links, :list, default: []
  attr :selection, :any, default: nil
  attr :active_links, :list, default: []
  attr :unavailable, :list, default: []
  attr :generation, :string, default: ""

  def dissector(assigns) do
    bindings = if assigns.case, do: assigns.case["explanation"]["bindings"], else: []

    assigns =
      assign(assigns,
        bindings: bindings,
        binding_index: min(assigns.binding_index, max(length(bindings) - 1, 0))
      )

    ~H"""
    <section class="instrument" id="dissector">
      <header>
        <span class="section-number">02</span><h2>Why this check has that result</h2>
      </header>
      <p :if={@reading["kind"] == "native_lean"}>
        Native Lean statement. No executable Elixir counterpart.
      </p>
      <p class="scope-note" id="connection-scope">
        Clause ↔ proof links are reviewed source-reading aids, not Lean goal states,
        kernel dependencies or acceptance evidence.
      </p>
      <p :if={!@reading["reading_current"]} id="links-stale" class="scope-note connection-unavailable">
        Source-bound reading notes are stale for the current law source. Clause/proof links are unavailable; ordinary checks remain accessible.
      </p>
      <p :if={@reading["reading_current"] && @reading["connections"] == []} id="links-unsupported" class="scope-note">
        No reviewed proof correspondence is available for this claim. Its ordinary source and checks remain accessible.
      </p>
      <p :for={reason <- @unavailable} class="scope-note connection-unavailable">Reading unavailable: {reason}</p>
      <div :if={@case}>
        <p id="binding-count">
          {if length(@bindings) == 1,
            do: "Values used for this check",
            else: "#{length(@bindings)} combinations checked"}
        </p>
        <.form
          :if={length(@bindings) > 1}
          for={to_form(%{"index" => @binding_index})}
          id="binding-choice"
          phx-change="select_binding"
        >
          <.input
            name="index"
            value={@binding_index}
            type="select"
            label="Inspect values"
            options={
              Enum.map(Enum.with_index(@bindings), fn {binding, index} ->
                {"#{index + 1}: " <>
                   Enum.map_join(binding["values"], ", ", fn {name, value} ->
                     name <> "=" <> term(value)
                   end), index}
              end)
            }
          />
        </.form>
        <div class="segmented" aria-label="Output being inspected">
          <button
            phx-click="basis"
            phx-value-value="actual"
            aria-pressed={to_string(@basis == "actual")}
          >Code result</button>
          <button
            phx-click="basis"
            phx-value-value="candidate"
            aria-pressed={to_string(@basis == "candidate")}
          >Alternative result</button>
        </div>
        <article
          :for={{binding, index} <- Enum.with_index(@bindings)}
          :if={index == @binding_index}
          class="binding"
          id={"binding-#{index}"}
        >
          <h3>Values {index + 1}</h3>
          <dl class="binding-values">
            <div :for={{name, value} <- binding["values"]}>
              <dt>{name}</dt><dd>{term(value)}</dd>
            </div>
          </dl>
          <p :if={binding["error"]} role="alert">{binding["error"]}</p>
          <div :if={binding["requires"]}>
            <.clause_table
              title="When this rule applies"
              node={binding["requires"]}
              phase="requires"
              binding={index}
              links={@links}
              selection={@selection}
              active_links={@active_links}
              generation={@generation}
            />
            <.clause_table
              :if={binding[@basis]}
              title="What the rule requires"
              node={binding[@basis]}
              phase={@basis}
              binding={index}
              links={@links}
              selection={@selection}
              active_links={@active_links}
              generation={@generation}
            />
            <p :if={!binding[@basis]} class="scope-note" id="outside-domain">
              This rule does not apply to this input.
            </p>
          </div>
        </article>
        <p :if={@case["explanation"]["bindings"] == []} id="unavailable-binding">
          {@case["explanation"]["reason"]}
        </p>
        <p class="scope-note">{@case["explanation"]["reason"]}</p>
      </div>
      <div :if={@helper} class="helper-definition" id="helper-definition">
        <div class="section-heading">
          <h3>{@helper["expression"]}</h3><button phx-click="close_helper">Close</button>
        </div>
        <p :if={@helper["source_path"]}>
          <code>{@helper["source_path"]}:{@helper["source_line"]}</code>
        </p>
        <.clause_table title="Definition on these values" node={@helper} phase="helper" binding={0} />
      </div>
      <details class="full-contract">
        <summary>Full claim expressions</summary>
        <div :if={@reading["contract"]["status"] == "source_read"}>
          <div class="contract-source">
            <span>requires</span><code id="requires-expression">{@reading["contract"]["requires"]}</code>
          </div>
          <div class="contract-source">
            <span>expects</span><code id="expects-expression">{@reading["contract"]["expects"]}</code>
          </div>
        </div>
      </details>
      <a
        :if={@reading["law"]["file"]}
        href={source_url(@reading, @reading["law"]["file"])}
        target="_blank"
        rel="noopener"
      >Full law source ↗</a>
    </section>
    """
  end

  attr :node, :map, required: true
  attr :title, :string, required: true
  attr :phase, :string, required: true
  attr :binding, :integer, required: true
  attr :links, :list, default: []
  attr :selection, :any, default: nil
  attr :active_links, :list, default: []
  attr :generation, :string, default: ""

  def clause_table(assigns) do
    ~H"""
    <section class="clause-table">
      <h3>{@title} <.truth value={@node["value"]} /></h3>
      <.logic
        node={@node} root={@node} phase={@phase} binding={@binding} path={[]}
        links={@links} selection={@selection} active_links={@active_links}
        generation={@generation}
      />
    </section>
    """
  end

  attr :node, :map, required: true

  attr :root, :map, required: true
  attr :phase, :string, required: true
  attr :binding, :integer, required: true
  attr :path, :list, required: true
  attr :links, :list, default: []
  attr :selection, :any, default: nil
  attr :active_links, :list, default: []
  attr :generation, :string, default: ""

  def logic(assigns) do
    op = operator(assigns.node)
    address = Enum.join(assigns.path, ".")

    related =
      Enum.filter(assigns.links, fn link ->
        link["phase"] == assigns.phase and link["path"] == address and
          link["binding"] == assigns.binding
      end)

    active =
      Enum.any?(assigns.active_links, fn link ->
        link["phase"] == assigns.phase and link["path"] == address and
          link["binding"] == assigns.binding
      end)

    selected =
      match?(%{type: :clause}, assigns.selection) and
        assigns.selection.phase == assigns.phase and
        assigns.selection.path == address and
        assigns.selection.binding == assigns.binding

    children = Enum.with_index(assigns.node["children"] || [])

    assigns =
      assign(assigns,
        op: op,
        address: address,
        related: related,
        active: active,
        selected: selected,
        children: children
      )

    ~H"""
    <div
      class={[
        "logic-node",
        @op in [:and, :or, :not] && "logic-group",
        @node["status"] == "not_evaluated" && "not-evaluated",
        @active && "connected-clause",
        @selected && "selected-clause"
      ]}
      id={if @phase != "helper", do: "clause-#{@binding}-#{@phase}-#{if @address == "", do: "root", else: String.replace(@address, ".", "-")}"}
    >
      <div class="logic-line logic-leaf">
        <span :if={@op in [:and, :or, :not]} class="logic-operator">{String.upcase(Atom.to_string(@op))}</span>
        <button
          :if={@phase != "helper"}
          class="clause-select"
          phx-click="select_clause"
          phx-value-phase={@phase}
          phx-value-binding={@binding}
          phx-value-path={@address}
          phx-value-generation={@generation}
          aria-pressed={to_string(@selected)}
          title="Select this observed condition"
        >{@node["expression"]}</button>
        <code :if={@phase == "helper"}>{@node["expression"]}</code>
        <span :if={@node["status"] == "not_evaluated"} class="unevaluated-value">Not evaluated</span>
        <.truth :if={@node["status"] != "not_evaluated"} value={@node["value"]} />
        <strong :if={inline_values(@node, @op)} class="inline-values">{inline_values(@node, @op)}</strong>
        <button
          :if={expandable?(@node) && @phase != "helper"}
          class="text-button"
          phx-click="helper"
          phx-value-phase={@phase}
          phx-value-binding={@binding}
          phx-value-path={@address}
        >Definition</button>
        <small :if={@related != []} class="connection-marker">Related proof passage ({length(@related)})</small>
        <small :if={@selected && @related == []} class="scope-note">No reviewed proof passage for this condition</small>
      </div>
      <div :if={@children != []} class="logic-children">
        <.logic
          :for={{child, index} <- @children}
          node={child} root={@root} phase={@phase} binding={@binding} path={@path ++ [index]}
          links={@links} selection={@selection} active_links={@active_links}
          generation={@generation}
        />
      </div>
    </div>
    """
  end

  defp operator(%{"expression" => expression}) do
    case Code.string_to_quoted(expression) do
      {:ok, {op, _, _}}
      when op in [:and, :or, :not, :if, :case, :<=, :<, :>=, :>, :==, :===, :!=, :!==, :in] ->
        op

      _ ->
        nil
    end
  end

  defp inline_values(%{"children" => [left, right]}, op)
       when op in [:<=, :<, :>=, :>, :==, :===, :!=, :!==, :in] do
    symbol =
      %{
        :< => "<",
        :<= => "≤",
        :> => ">",
        :>= => "≥",
        :== => "=",
        :=== => "≡",
        :!= => "≠",
        :!== => "≠",
        :in => "∈"
      }[op]

    term(left["value"]) <> " " <> symbol <> " " <> term(right["value"])
  end

  defp inline_values(_, _), do: nil

  attr :value, :any, required: true

  def truth(assigns) do
    ~H"""
    <span class={["truth", @value === true && "yes", @value === false && "no"]}>{term(@value)}</span>
    """
  end

  defp expandable?(node), do: Enum.any?(node["children"], &(&1["helper"] != nil))

  def term(true), do: "true"
  def term(false), do: "false"
  def term(nil), do: "—"
  def term(%{"atom" => atom}), do: ":" <> atom
  def term(%{"lookup_found" => entry}), do: "found " <> term(entry)

  def term(%{"key" => key, "amount" => amount, "status" => status}),
    do: "#{key} · #{amount}¢ · #{status}"

  def term(%{"amount_limit" => limit, "used_amount" => used, "entries" => entries}),
    do: "account: #{used}/#{limit}¢; #{length(entries)} entries"

  def term(%{"type" => "request", "key" => key, "amount" => amount}),
    do: "request(#{key}, #{amount}¢)"

  def term(%{"type" => type, "key" => key}), do: "#{type}(#{key})"
  def term(%{"after" => state, "result" => result}), do: result <> "; " <> term(state)
  def term(%{"unavailable" => _}), do: "outside display bounds"
  def term(list) when is_list(list), do: "[" <> Enum.map_join(list, ", ", &term/1) <> "]"
  def term(value) when is_integer(value) or is_binary(value), do: to_string(value)

  def source_url(reading, path) do
    source = Enum.find(reading["sources"], &(&1["path"] == path))

    if source,
      do: "/claims/#{reading["slug"]}/source/#{source["id"]}/#{source["sha256"]}",
      else: nil
  end
end
