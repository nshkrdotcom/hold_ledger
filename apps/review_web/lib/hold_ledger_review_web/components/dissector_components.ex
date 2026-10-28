defmodule HoldLedgerReviewWeb.DissectorComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html

  attr :case, :map, default: nil
  attr :reading, :map, required: true
  attr :basis, :string, default: "candidate"
  attr :helper, :map, default: nil
  attr :binding_index, :integer, default: 0

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
        <span class="section-number">02</span><h2>Evaluated clauses</h2>
      </header>
      <p :if={@reading["kind"] == "native_lean"}>
        Native Lean statement. No executable Elixir counterpart.
      </p>
      <div :if={@case}>
        <p id="binding-count">
          {length(@bindings)} source-derived bindings · all remain part of this case result
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
            label="Inspect binding"
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
          >Ledger output</button>
          <button
            phx-click="basis"
            phx-value-value="candidate"
            aria-pressed={to_string(@basis == "candidate")}
          >Hypothetical output</button>
        </div>
        <article
          :for={{binding, index} <- Enum.with_index(@bindings)}
          :if={index == @binding_index}
          class="binding"
          id={"binding-#{index}"}
        >
          <h3>Binding {index + 1}</h3>
          <dl class="binding-values">
            <div :for={{name, value} <- binding["values"]}>
              <dt>{name}</dt><dd>{term(value)}</dd>
            </div>
          </dl>
          <p :if={binding["error"]} role="alert">{binding["error"]}</p>
          <div :if={binding["requires"]}>
            <.clause_table
              title="When the law applies"
              node={binding["requires"]}
              phase="requires"
              binding={index}
            />
            <.clause_table
              :if={binding[@basis]}
              title="What the output must satisfy"
              node={binding[@basis]}
              phase={@basis}
              binding={index}
            />
            <p :if={!binding[@basis]} class="scope-note" id="outside-domain">
              Precondition false. This law makes no promise for this input.
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

  def clause_table(assigns) do
    ~H"""
    <section class="clause-table">
      <h3>{@title} <.truth value={@node["value"]} /></h3>
      <.logic node={@node} root={@node} phase={@phase} binding={@binding} />
    </section>
    """
  end

  attr :node, :map, required: true

  attr :root, :map, required: true
  attr :phase, :string, required: true
  attr :binding, :integer, required: true

  def logic(assigns) do
    op = operator(assigns.node)

    assigns =
      assign(assigns,
        op: op,
        children: logical_children(assigns.node, op),
        helpers: helper_children(assigns.node)
      )

    ~H"""
    <div class={["logic-node", @node["status"] == "not_evaluated" && "not-evaluated"]}>
      <div :if={@op in [:and, :or, :not] && @node["status"] != "not_evaluated"} class="logic-group">
        <div class="logic-group-heading">
          <span class="logic-operator">{String.upcase(Atom.to_string(@op))}</span><.truth value={
            @node["value"]
          } />
        </div>
        <div class="logic-children">
          <.logic
            :for={child <- @children}
            node={child}
            root={@root}
            phase={@phase}
            binding={@binding}
          />
        </div>
      </div>
      <div
        :if={
          (@op not in [:and, :or, :not, :if, :case] && @node["helper"] == nil) ||
            @node["status"] == "not_evaluated"
        }
        class="logic-leaf"
      >
        <code>{@node["expression"]}</code>
        <strong :if={inline_values(@node, @op)} class="inline-values">{inline_values(@node, @op)}</strong>
        <div :if={!inline_values(@node, @op) && operands(@node) != ""} class="inline-values">
          {operands(@node)}
        </div>
        <button
          :if={expandable?(@node) && @phase != "helper"}
          class="text-button"
          phx-click="helper"
          phx-value-phase={@phase}
          phx-value-binding={@binding}
          phx-value-path={Enum.join(node_path(@root, @node) || [], ".")}
        >Definition</button>
        <span :if={@node["status"] != "not_evaluated"}><.truth value={@node["value"]} /></span><span :if={
          @node["status"] == "not_evaluated"
        }>Not evaluated</span>
      </div>
      <div
        :if={@helpers != [] && @node["status"] != "not_evaluated"}
        class="helper-logic"
      >
        <.logic :for={child <- @helpers} node={child} root={@root} phase={@phase} binding={@binding} />
      </div>
    </div>
    """
  end

  defp helper_children(%{"helper" => helper, "children" => children}) when helper != nil,
    do: children

  defp helper_children(node) do
    case Code.string_to_quoted(node["expression"]) do
      {:ok, {op, _, _}} when op in [:if, :case] ->
        node["children"]

      {:ok, {{:., _, [_, name]}, _, _}} when name in [:request_eligible?, :exposed_entry?] ->
        node["children"]

      {:ok, {name, _, _}} when name in [:request_eligible?, :exposed_entry?] ->
        node["children"]

      _ ->
        []
    end
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

  defp logical_children(node, op) when op in [:and, :or] do
    Enum.flat_map(node["children"], fn child ->
      if child["status"] != "not_evaluated" and operator(child) == op,
        do: logical_children(child, op),
        else: [child]
    end)
  end

  defp logical_children(node, _), do: node["children"]

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

  defp node_path(node, node), do: []

  defp node_path(root, target) do
    root["children"]
    |> Enum.with_index()
    |> Enum.find_value(fn {child, index} ->
      case node_path(child, target) do
        nil -> nil
        path -> [index | path]
      end
    end)
  end

  defp expandable?(node), do: Enum.any?(node["children"], &(&1["helper"] != nil))

  defp operands(node) do
    node["children"]
    |> Enum.reject(&(&1["helper"] != nil))
    |> Enum.map_join(" · ", &term(&1["value"]))
  end

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
