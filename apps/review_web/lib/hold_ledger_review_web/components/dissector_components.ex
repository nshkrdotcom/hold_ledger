defmodule HoldLedgerReviewWeb.DissectorComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html

  attr :case, :map, default: nil
  attr :reading, :map, required: true
  attr :basis, :string, default: "candidate"
  attr :helper, :map, default: nil

  def dissector(assigns) do
    ~H"""
    <section class="instrument" id="dissector">
      <header>
        <span class="section-number">02</span><h2>Contract deconstructor</h2>
      </header>
      <div :if={@reading["contract"]["status"] == "source_read"}>
        <div class="contract-source">
          <span>requires</span><code id="requires-expression">{@reading["contract"]["requires"]}</code>
        </div>
        <div class="contract-source">
          <span>expects</span><code id="expects-expression">{@reading["contract"]["expects"]}</code>
        </div>
      </div>
      <p :if={@reading["kind"] == "native_lean"}>
        Native Lean statement. No executable Elixir counterpart.
      </p>
      <div :if={@case}>
        <div class="segmented" aria-label="Output being inspected">
          <button phx-click="basis" phx-value-value="actual" aria-pressed={@basis == "actual"}>Ledger output</button>
          <button phx-click="basis" phx-value-value="candidate" aria-pressed={@basis == "candidate"}>Hypothetical output</button>
        </div>
        <article
          :for={{binding, index} <- Enum.with_index(@case["explanation"]["bindings"])}
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
    assigns = assign(assigns, :clauses, frontier(assigns.node))

    ~H"""
    <section class="clause-table">
      <h3>{@title} <.truth value={@node["value"]} /></h3>
      <table>
        <thead>
          <tr>
            <th>Source expression</th><th>Values</th><th>Result</th>
          </tr>
        </thead><tbody>
          <tr
            :for={{node, index} <- Enum.with_index(@clauses)}
            data-expression={node["expression"]}
            data-result={inspect(node["value"])}
          >
            <td>
              <code>{short(node["expression"])}</code><button
                :if={expandable?(node) && @phase != "helper"}
                class="text-button"
                phx-click="helper"
                phx-value-phase={@phase}
                phx-value-binding={@binding}
                phx-value-index={index}
              >Definition</button>
            </td>
            <td class="operand-values">{operands(node)}</td>
            <td>
              <span :if={node["status"] == "not_evaluated"} class="muted">not evaluated</span><.truth
                :if={node["status"] != "not_evaluated"}
                value={node["value"]}
              />
            </td>
          </tr>
        </tbody>
      </table>
    </section>
    """
  end

  attr :value, :any, required: true

  def truth(assigns) do
    ~H"""
    <span class={["truth", @value === true && "yes", @value === false && "no"]}>{term(@value)}</span>
    """
  end

  def frontier(nil), do: []

  def frontier(%{"helper" => helper, "children" => children}) when helper != nil,
    do: Enum.flat_map(children, &frontier/1)

  def frontier(%{"expression" => expression, "children" => [child]} = node) do
    if String.contains?(expression, "request_eligible?") or
         String.contains?(expression, "exposed_entry?"), do: frontier(child), else: [node]
  end

  def frontier(%{"expression" => expression, "children" => children} = node) do
    cond do
      node["status"] == "not_evaluated" ->
        [node]

      node["helper"] != nil ->
        Enum.flat_map(children, &frontier/1)

      String.starts_with?(expression, "if ") or String.starts_with?(expression, "case ") ->
        Enum.flat_map(children, &frontier/1)

      String.contains?(expression, " and ") or String.contains?(expression, " or ") ->
        Enum.flat_map(children, &frontier/1)

      true ->
        [node]
    end
  end

  defp expandable?(node), do: Enum.any?(node["children"], &(&1["helper"] != nil))

  defp operands(node) do
    node["children"]
    |> Enum.reject(&(&1["helper"] != nil))
    |> Enum.map_join(" · ", &term(&1["value"]))
  end

  defp short(text), do: String.replace(text, "HoldLedger.", "")

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
