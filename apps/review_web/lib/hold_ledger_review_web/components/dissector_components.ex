defmodule HoldLedgerReviewWeb.DissectorComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html
  alias HoldLedgerReview.ConditionOutline

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
  attr :changed_sources, :list, default: []
  attr :stage, :integer, default: 0

  def dissector(assigns) do
    bindings = if assigns.case, do: assigns.case["explanation"]["bindings"], else: []
    source_paths = MapSet.new(Enum.map(assigns.reading["sources"], & &1["path"]))
    changed_sources = Enum.filter(assigns.changed_sources, &MapSet.member?(source_paths, &1))

    outlines =
      Enum.map(bindings, fn binding ->
        Map.new(~w(requires actual candidate), fn phase ->
          {phase,
           ConditionOutline.project(
             binding[phase],
             phase,
             assigns.reading["condition_groups"] || [],
             changed_sources
           )}
        end)
      end)

    assigns =
      assign(assigns,
        bindings: bindings,
        outlines: outlines,
        changed_sources: changed_sources,
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
      <details :if={@changed_sources != []} open class="source-comparison-attention" id="compared-source-attention">
        <summary>Compared sources changed · inspect source and affected conditions</summary>
        <ul>
          <li :for={path <- @changed_sources}><code>{path}</code></li>
        </ul>
        <p class="scope-note">A changed file is not a demonstrated change in predicate truth.</p>
      </details>
      <p
        :if={@reading["reading_status"] == "stale"}
        id="links-stale"
        class="scope-note connection-unavailable"
      >
        Source-bound reading notes are stale for the current law source. Clause/proof links are unavailable; ordinary checks remain accessible.
      </p>
      <p
        :if={@reading["reading_status"] != "stale" && @reading["connections"] == []}
        id="links-unsupported"
        class="scope-note"
      >
        No reviewed proof correspondence is available for this claim. Its ordinary source and checks remain accessible.
      </p>
      <details :if={@unavailable != []} class="unavailable-readings">
        <summary>{length(@unavailable)} source-reading relationships unavailable</summary>
        <p :for={reason <- @unavailable} class="scope-note connection-unavailable">
          Reading unavailable: {reason}
        </p>
      </details>
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
            phx-value-basis="actual"
            aria-pressed={to_string(@basis == "actual")}
          >Code result</button>
          <button
            phx-click="basis"
            phx-value-basis="candidate"
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
              groups={Enum.at(@outlines, index)["requires"]}
              proof_steps={@reading["proof_steps"]}
              stage={@stage}
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
              groups={Enum.at(@outlines, index)[@basis]}
              proof_steps={@reading["proof_steps"]}
              stage={@stage}
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
  attr :groups, :list, default: []
  attr :proof_steps, :list, default: []
  attr :stage, :integer, default: 0

  def clause_table(assigns) do
    groups =
      if assigns.groups == [],
        do: ConditionOutline.project(assigns.node, assigns.phase, []),
        else: assigns.groups

    assigns = assign(assigns, :groups, groups)

    ~H"""
    <section class="clause-table" id={"outline-#{@binding}-#{@phase}"}>
      <h3>{@title} <.truth value={@node["value"]} /></h3>
      <p class="scope-note">Groups count only the named, observed conditions. The original tree is available below.</p>
      <.condition_group
        :for={group <- @groups}
        group={group}
        root={@node}
        phase={@phase}
        binding={@binding}
        links={@links}
        selection={@selection}
        active_links={@active_links}
        generation={@generation}
        proof_steps={@proof_steps}
        stage={@stage}
      />
      <details
        class="original-expression-tree"
        id={"complete-tree-#{@binding}-#{@phase}"}
        open={tree_selection?(@selection, @phase, @binding, @groups)}
      >
        <summary>Complete observed expression tree · original source structure and paths</summary>
        <.logic
          node={@node}
          root={@node}
          phase={@phase}
          binding={@binding}
          path={[]}
          links={@links}
          selection={@selection}
          active_links={@active_links}
          generation={@generation}
          mode="tree"
          id_prefix="tree-clause"
          tree_selection={tree_selection?(@selection, @phase, @binding, @groups)}
          proof_steps={@proof_steps}
          stage={@stage}
        />
      </details>
    </section>
    """
  end

  attr :group, :map, required: true
  attr :root, :map, required: true
  attr :phase, :string, required: true
  attr :binding, :integer, required: true
  attr :links, :list, default: []
  attr :selection, :any, default: nil
  attr :active_links, :list, default: []
  attr :generation, :string, default: ""
  attr :proof_steps, :list, default: []
  attr :stage, :integer, default: 0

  def condition_group(assigns) do
    linked =
      Enum.any?(assigns.group.observations, fn observed ->
        address = Enum.join(observed.path, ".")

        Enum.any?(assigns.active_links, fn link ->
          link["phase"] == assigns.phase and link["binding"] == assigns.binding and
            link["path"] == address
        end)
      end)

    selected_path =
      case assigns.selection do
        %{type: :clause, phase: phase, binding: binding, path: path}
          when phase == assigns.phase and binding == assigns.binding -> path
        %{type: :step, target: %{phase: phase, binding: binding, path: path}}
          when phase == assigns.phase and binding == assigns.binding -> path
        _ -> nil
      end

    selected_here = is_binary(selected_path) and
      Enum.any?(assigns.group.observations, &(Enum.join(&1.path, ".") == selected_path))

    assigns = assign(assigns, :open_group, !assigns.group.collapsed? || linked || selected_here)

    ~H"""
    <details
      id={"group-#{@binding}-#{@phase}-#{@group.id}"}
      class={["condition-group", @group.attention? && "condition-attention"]}
      open={@open_group}
    >
      <summary>
        <strong>{@group.title}</strong>
        <span class="group-counts">{count_summary(@group.counts)}</span>
        <small :if={@group.changed_source?} class="connection-unavailable">
          Compared source file changed: {@group.source_path}
        </small>
      </summary>
      <div class="condition-rows">
        <.logic
          :for={observation <- @group.observations}
          node={observation.node}
          root={@root}
          phase={@phase}
          binding={@binding}
          path={observation.path}
          links={@links}
          selection={@selection}
          active_links={@active_links}
          generation={@generation}
          mode="summary"
          proof_steps={@proof_steps}
          stage={@stage}
        />
      </div>
    </details>
    """
  end

  defp count_summary(counts) do
    ~w(true false not_evaluated unavailable)
    |> Enum.filter(&(counts[&1] > 0))
    |> Enum.map_join(" · ", fn
      "not_evaluated" -> "#{counts["not_evaluated"]} not evaluated"
      key -> "#{counts[key]} #{key}"
    end)
  end

  defp tree_selection?(selection, phase, binding, groups) do
    target =
      case selection do
        %{type: :clause, phase: ^phase, binding: ^binding, path: path} -> path
        %{type: :step, target: %{phase: ^phase, binding: ^binding, path: path}} -> path
        _ -> nil
      end

    is_binary(target) and
      not Enum.any?(groups, fn group ->
        Enum.any?(group.observations, &(Enum.join(&1.path, ".") == target))
      end)
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
  attr :mode, :string, default: "tree"
  attr :id_prefix, :string, default: "clause"
  attr :proof_steps, :list, default: []
  attr :stage, :integer, default: 0
  attr :tree_selection, :boolean, default: false

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
      case assigns.selection do
        %{type: :clause, phase: phase, path: path, binding: binding} ->
          phase == assigns.phase and path == address and binding == assigns.binding

        %{type: :step, target: %{phase: phase, path: path, binding: binding}} ->
          phase == assigns.phase and path == address and binding == assigns.binding

        _ ->
          false
      end

    excerpts =
      for link <- related,
          i <- link["steps"],
          step = Enum.at(assigns.proof_steps, i),
          step && is_integer(step["line"]),
          do: %{index: i, step: step, relation: link["relation"]}

    excerpts = Enum.uniq_by(excerpts, & &1.index)
    chosen = Enum.find(excerpts, &(&1.index == assigns.stage)) || List.first(excerpts)

    children = Enum.with_index(assigns.node["children"] || [])

    assigns =
      assign(assigns,
        op: op,
        address: address,
        related: related,
        active: active,
        selected: selected && (assigns.mode == "summary" || assigns.tree_selection),
        excerpts: excerpts,
        chosen: chosen,
        children: children,
        compact_label: node_label(assigns.node, op),
        expand_children: assigns.mode == "tree" && expand_children?(assigns, op)
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
      id={
        if @phase != "helper",
          do:
            "#{@id_prefix}-#{@binding}-#{@phase}-#{if @address == "", do: "root", else: String.replace(@address, ".", "-")}"
      }
    >
      <div class="logic-line logic-leaf">
        <span :if={@op in [:and, :or, :not]} class="logic-operator">{String.upcase(
          Atom.to_string(@op)
        )}</span>
        <button
          :if={@phase != "helper"}
          class="clause-select"
          phx-click="select_clause"
          phx-value-phase={@phase}
          phx-value-binding={@binding}
          phx-value-path={@address}
          phx-value-generation={@generation}
          aria-pressed={to_string(@selected)}
          title={"Select observed condition at path #{if @address == "", do: "root", else: @address}"}
        >{@compact_label}</button>
        <code :if={@phase == "helper"}>{@compact_label}</code>
        <span :if={@node["status"] == "not_evaluated"} class="unevaluated-value">Not evaluated</span>
        <span :if={@node["status"] in ["error", "unavailable"]} class="unevaluated-value">Unavailable</span>
        <.truth :if={@node["status"] not in ["not_evaluated", "error", "unavailable"]} value={@node["value"]} />
        <strong :if={@node["status"] not in ["not_evaluated", "error", "unavailable"] && inline_values(@node, @op)} class="inline-values">{inline_values(@node, @op)}</strong>
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
      <section :if={@selected && @chosen} class="linked-excerpt" id={"reading-excerpt-#{@binding}-#{@phase}"}>
        <h4>Related Lean source reading</h4>
        <p>{@chosen.relation}</p>
        <nav aria-label="Related Lean passages" class="excerpt-stages">
          <button
            :for={passage <- @excerpts}
            phx-click="proof_stage"
            phx-value-index={passage.index}
            aria-pressed={to_string(passage.index == @chosen.index)}
          >{passage.index + 1}. {passage.step["title"]}</button>
        </nav>
        <p class="excerpt-location">{@chosen.step["path"]}:{@chosen.step["line"]} · {@chosen.step["reason"]}</p>
        <pre><code>{@chosen.step["code"]}</code></pre>
        <p class="scope-note">Reviewed source correspondence, not a proof of this clause in isolation.</p>
      </section>
      <div :if={@children != [] && @expand_children} class="logic-children">
        <.logic
          :for={{child, index} <- @children}
          node={child}
          root={@root}
          phase={@phase}
          binding={@binding}
          path={@path ++ [index]}
          links={@links}
          selection={@selection}
          active_links={@active_links}
          generation={@generation}
          mode={@mode}
          id_prefix={@id_prefix}
          tree_selection={@tree_selection}
          proof_steps={@proof_steps}
          stage={@stage}
        />
      </div>
      <details :if={@children != [] && !@expand_children && @mode == "tree"} class="clause-details">
        <summary>Inspect values and definition</summary>
        <div class="logic-children">
          <.logic
            :for={{child, index} <- @children}
            node={child}
            root={@root}
            phase={@phase}
            binding={@binding}
            path={@path ++ [index]}
            links={@links}
            selection={@selection}
            active_links={@active_links}
            generation={@generation}
            mode={@mode}
            id_prefix={@id_prefix}
            tree_selection={@tree_selection}
            proof_steps={@proof_steps}
            stage={@stage}
          />
        </div>
      </details>
    </div>
    """
  end

  defp node_label(%{"helper" => name}, _) when is_binary(name), do: name <> " definition"
  defp node_label(_, :and), do: "All conditions"
  defp node_label(_, :or), do: "Any condition"
  defp node_label(_, :if), do: "Conditional branches"
  defp node_label(_, :case), do: "Selected branch"
  defp node_label(node, _), do: node["expression"]

  defp expand_children?(assigns, op) do
    logical? = op in [:and, :or, :not, :if, :case]

    eligibility? =
      assigns.node["helper"] == "request_eligible?/3" or
        Enum.any?(assigns.node["children"] || [], &(&1["helper"] == "request_eligible?/3"))

    logical? or eligibility? or selected_descendant?(assigns)
  end

  defp selected_descendant?(assigns) do
    prefix = Enum.join(assigns.path, ".")

    linked = Enum.any?(assigns.active_links, fn link ->
      link["phase"] == assigns.phase and link["binding"] == assigns.binding and
        descendant_path?(prefix, link["path"])
    end)

    selected_path =
      case assigns.selection do
        %{type: :clause, phase: phase, binding: binding, path: path}
          when phase == assigns.phase and binding == assigns.binding -> path
        %{type: :step, target: %{phase: phase, binding: binding, path: path}}
          when phase == assigns.phase and binding == assigns.binding -> path
        _ -> nil
      end

    linked or (is_binary(selected_path) and descendant_path?(prefix, selected_path))
  end

  defp descendant_path?("", path), do: path != ""
  defp descendant_path?(prefix, path), do: String.starts_with?(path, prefix <> ".")

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
