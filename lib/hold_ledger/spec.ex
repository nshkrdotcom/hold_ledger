defmodule HoldLedger.Spec do
  @moduledoc """
  Independent executable authorization-hold specification.

  This module computes the invariant, the normative transition oracle, and
  result/effect predicates directly from the specification guide. It has no dependency
  on the reducer or any of its helpers. `expected_step/2` recalculates the
  cached counters from the resulting entries instead of applying reducer deltas.
  All transition functions assume an initial state satisfying `valid?/1`.
  """

  @type status :: :reserved | :sent | :unknown | :authorized | :voiding | :declined | :voided
  @type entry :: {integer(), pos_integer(), status()}
  @type state ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), [entry()]}

  @doc "True precisely for statuses still consuming one hold and their stored amount."
  def holding?(:reserved), do: true
  def holding?(:sent), do: true
  def holding?(:unknown), do: true
  def holding?(:authorized), do: true
  def holding?(:voiding), do: true
  def holding?(_), do: false

  @doc "True precisely for the two permanently released statuses."
  def terminal?(:declined), do: true
  def terminal?(:voided), do: true
  def terminal?(_), do: false

  @doc "Recognizes a valid status atom, independently of state validity."
  def known_status?(s), do: holding?(s) or terminal?(s)

  @doc "Rejects malformed entry tuples, improper tails and non-lists."
  def proper_entries?([]), do: true

  def proper_entries?([{k, amount, status} | rest])
      when is_integer(k) and is_integer(amount) and amount > 0 do
    known_status?(status) and proper_entries?(rest)
  end

  def proper_entries?(_), do: false

  @doc "True if no entry key occurs twice, including among released entries."
  def unique_keys?(entries) when is_list(entries), do: unique_keys_seen?(entries, [])
  def unique_keys?(_), do: false

  defp unique_keys_seen?([], _seen), do: true

  defp unique_keys_seen?([{k, _, _} | rest], seen) when is_integer(k) do
    not seen?(seen, k) and unique_keys_seen?(rest, [k | seen])
  end

  defp unique_keys_seen?(_, _), do: false

  defp seen?([], _), do: false
  defp seen?([first | tail], key), do: first == key or seen?(tail, key)

  @doc "Independent lookup over a well-formed list; a released key remains findable."
  def lookup([], _key), do: :not_found

  def lookup([{entry_key, _amount, _status} = entry | rest], key) do
    if entry_key == key, do: {:ok, entry}, else: lookup(rest, key)
  end

  def lookup(_, _), do: :not_found

  def has_key?(entries, key) do
    case lookup(entries, key) do
      {:ok, _} -> true
      :not_found -> false
    end
  end

  @doc "Sum of amounts of still holding entries (expects proper well-formed entries)."
  def hold_amount([]), do: 0

  def hold_amount([{_, amount, status} | rest]) do
    if holding?(status), do: amount + hold_amount(rest), else: hold_amount(rest)
  end

  @doc "Count of holding entries, including unknown and authorized."
  def hold_count([]), do: 0

  def hold_count([{_, _, status} | rest]) do
    if holding?(status), do: 1 + hold_count(rest), else: hold_count(rest)
  end

  @doc "Independent invariant; returns false (never raises) for malformed states."
  def valid?({amount_limit, hold_limit, used_amount, used_holds, entries})
      when is_integer(amount_limit) and is_integer(hold_limit) and
             is_integer(used_amount) and is_integer(used_holds) do
    nonnegative_state_valid?(amount_limit, hold_limit, used_amount, used_holds, entries)
  end

  def valid?(_), do: false

  defp nonnegative_state_valid?(amount_limit, hold_limit, used_amount, used_holds, entries)
       when amount_limit >= 0 and hold_limit >= 0 and used_amount >= 0 and used_holds >= 0 do
    proper_entries?(entries) and unique_keys?(entries) and
      used_amount == hold_amount(entries) and used_holds == hold_count(entries) and
      used_amount <= amount_limit and used_holds <= hold_limit
  end

  defp nonnegative_state_valid?(_, _, _, _, _), do: false

  @doc "An admissible request witness includes uniqueness, both caps and shape."
  def request_eligible?(state, key, amount)
      when is_integer(key) and is_integer(amount) and amount > 0 do
    if valid?(state) do
      {amount_limit, hold_limit, used_amount, used_holds, entries} = state

      not has_key?(entries, key) and used_holds < hold_limit and
        amount <= amount_limit - used_amount
    else
      false
    end
  end

  def request_eligible?(_, _, _), do: false

  @doc "Classification from the contract; excludes status atoms not returned as results."
  def applied_result?(:admitted), do: true
  def applied_result?(:dispatched), do: true
  def applied_result?(:marked_unknown), do: true
  def applied_result?(:restarted), do: true
  def applied_result?(:retried), do: true
  def applied_result?(:authorized), do: true
  def applied_result?(:declined), do: true
  def applied_result?(:voided), do: true
  def applied_result?(:voiding), do: true
  def applied_result?(_), do: false

  def not_applied_result?(:duplicate), do: true
  def not_applied_result?(:conflict), do: true
  def not_applied_result?(:insufficient_holds), do: true
  def not_applied_result?(:insufficient_amount), do: true
  def not_applied_result?(:stale), do: true
  def not_applied_result?(:not_found), do: true
  def not_applied_result?(:malformed), do: true
  def not_applied_result?(_), do: false

  @doc "The intended I/O term names a real post-transition entry in its required status."
  def effect_valid?({_, _, _, _, entries}, {:authorize, key, amount}) do
    lookup(entries, key) == {:ok, {key, amount, :sent}}
  end

  def effect_valid?({_, _, _, _, entries}, {:void, key}) do
    case lookup(entries, key) do
      {:ok, {^key, _amount, :voiding}} -> true
      _ -> false
    end
  end

  def effect_valid?(_, _), do: false

  @doc """
  Checks result/effect consistency, including the original identity and amount,
  both required intent-producing transitions, and empty rejected effects.
  The expected-state oracle is separately checked via `expected_step/2`.
  """
  def effects_valid?(before_state, event, after_state, result, effects) do
    if valid?(before_state) and valid?(after_state) do
      consistent_effects?(before_state, event, after_state, result, effects)
    else
      false
    end
  end

  defp consistent_effects?(before_state, event, after_state, result, effects) do
    cond do
      not_applied_result?(result) ->
        before_state == after_state and effects == []

      result == :dispatched ->
        authorize_intent?(before_state, event, after_state, effects, :reserved, :dispatch)

      result == :retried ->
        authorize_intent?(before_state, event, after_state, effects, :unknown, :retry)

      result == :voiding ->
        void_intent?(before_state, event, after_state, effects)

      applied_result?(result) ->
        effects == []

      true ->
        false
    end
  end

  defp authorize_intent?(
         {_, _, _, _, entries},
         {tag, key},
         after_state,
         effects,
         from,
         expected_tag
       )
       when tag == expected_tag do
    case lookup(entries, key) do
      {:ok, {^key, amount, ^from}} ->
        effects == [{:authorize, key, amount}] and
          effect_valid?(after_state, {:authorize, key, amount})

      _ ->
        false
    end
  end

  defp authorize_intent?(_, _, _, _, _, _), do: false

  defp void_intent?({_, _, _, _, entries}, {:void, key}, after_state, effects) do
    case lookup(entries, key) do
      {:ok, {^key, amount, :authorized}} ->
        effects == [{:void, key}] and
          lookup(elem(after_state, 4), key) == {:ok, {key, amount, :voiding}}

      {:ok, {^key, amount, :reserved}} ->
        effects == [] and lookup(elem(after_state, 4), key) == {:ok, {key, amount, :voided}}

      _ ->
        false
    end
  end

  defp void_intent?(_, _, _, _), do: false

  @doc "All keys already seen keep their amounts and remain present in the successor."
  def identity_preserved?({_, _, _, _, before_entries}, {_, _, _, _, after_entries}),
    do: identities_present?(before_entries, after_entries)

  def identity_preserved?(_, _), do: false

  defp identities_present?([], _), do: true

  defp identities_present?([{key, amount, _} | tail], after_entries) do
    case lookup(after_entries, key) do
      {:ok, {^key, ^amount, _}} -> identities_present?(tail, after_entries)
      _ -> false
    end
  end

  @doc "No existing non-authorized entry may become authorized without its valid result."
  def authorized_only_on_result?({_, _, _, _, before_entries}, event, {_, _, _, _, after_entries}) do
    authorizations_explained?(before_entries, after_entries, event)
  end

  def authorized_only_on_result?(_, _, _), do: false

  defp authorizations_explained?([], _, _), do: true

  defp authorizations_explained?([{key, _amount, status} | rest], after_entries, event) do
    case lookup(after_entries, key) do
      {:ok, {^key, _, :authorized}} when status != :authorized ->
        event == {:processor_result, key, :approved} and status in [:sent, :unknown] and
          authorizations_explained?(rest, after_entries, event)

      _ ->
        authorizations_explained?(rest, after_entries, event)
    end
  end

  @doc "Independent complete transition oracle: caches are recomputed from entries."
  def expected_step(state, {:request, key, amount})
      when is_integer(key) and is_integer(amount) and amount > 0 do
    expect_request(state, key, amount)
  end

  def expected_step(state, {:dispatch, key}) when is_integer(key) do
    expect_single(state, key, :reserved, :sent, :dispatched, :authorize)
  end

  def expected_step(state, {:timeout, key}) when is_integer(key) do
    expect_single(state, key, :sent, :unknown, :marked_unknown, :none)
  end

  def expected_step(state, :restart) do
    {restated(state, unknown_sent(elem(state, 4))), :restarted, []}
  end

  def expected_step(state, {:retry, key}) when is_integer(key) do
    expect_single(state, key, :unknown, :sent, :retried, :authorize)
  end

  def expected_step(state, {:processor_result, key, :approved}) when is_integer(key) do
    expect_choice(state, key, :authorized, :authorized)
  end

  def expected_step(state, {:processor_result, key, :declined}) when is_integer(key) do
    expect_choice(state, key, :declined, :declined)
  end

  def expected_step(state, {:void, key}) when is_integer(key) do
    expect_void(state, key)
  end

  def expected_step(state, {:void_confirmed, key}) when is_integer(key) do
    expect_single(state, key, :voiding, :voided, :voided, :none)
  end

  def expected_step(state, {:transport_ack, key}) when is_integer(key) do
    {state, :stale, []}
  end

  def expected_step(state, _) do
    {state, :malformed, []}
  end

  defp expect_request(
         {amount_limit, hold_limit, used_amount, used_holds, entries} = s,
         key,
         amount
       ) do
    case lookup(entries, key) do
      {:ok, {_, ^amount, _}} ->
        {s, :duplicate, []}

      {:ok, _} ->
        {s, :conflict, []}

      :not_found ->
        cond do
          used_holds >= hold_limit -> {s, :insufficient_holds, []}
          amount > amount_limit - used_amount -> {s, :insufficient_amount, []}
          true -> {restated(s, [{key, amount, :reserved} | entries]), :admitted, []}
        end
    end
  end

  defp expect_single({_, _, _, _, entries} = s, key, from, to, result, effect) do
    case lookup(entries, key) do
      :not_found ->
        {s, :not_found, []}

      {:ok, {_, amount, ^from}} ->
        next_state = restated(s, replacement(entries, key, to))
        effects = if effect == :authorize, do: [{:authorize, key, amount}], else: []
        {next_state, result, effects}

      {:ok, _} ->
        {s, :stale, []}
    end
  end

  defp expect_choice({_, _, _, _, entries} = s, key, new_status, result) do
    case lookup(entries, key) do
      :not_found ->
        {s, :not_found, []}

      {:ok, {_, _, status}} when status in [:sent, :unknown] ->
        {restated(s, replacement(entries, key, new_status)), result, []}

      _ ->
        {s, :stale, []}
    end
  end

  defp expect_void({_, _, _, _, entries} = s, key) do
    case lookup(entries, key) do
      :not_found ->
        {s, :not_found, []}

      {:ok, {_, _, :reserved}} ->
        {restated(s, replacement(entries, key, :voided)), :voided, []}

      {:ok, {_, _, :authorized}} ->
        {restated(s, replacement(entries, key, :voiding)), :voiding, [{:void, key}]}

      _ ->
        {s, :stale, []}
    end
  end

  defp restated({amount_limit, hold_limit, _, _, _}, entries) do
    {amount_limit, hold_limit, hold_amount(entries), hold_count(entries), entries}
  end

  defp replacement([], _, _), do: []

  defp replacement([{existing_key, amount, _} | rest], key, status)
       when existing_key == key,
       do: [{existing_key, amount, status} | rest]

  defp replacement([entry | rest], key, status),
    do: [entry | replacement(rest, key, status)]

  defp unknown_sent([]), do: []

  defp unknown_sent([{key, amount, :sent} | rest]),
    do: [{key, amount, :unknown} | unknown_sent(rest)]

  defp unknown_sent([entry | rest]), do: [entry | unknown_sent(rest)]

  # Derived proof predicates. These do not call the implementation or change
  # expected_step/2. They state the exact finite-list and status properties
  # used by the Lynx laws.

  @doc "Recognize a finite proper event list without restricting its elements."
  def proper_events?([]), do: true
  def proper_events?([_event | rest]), do: proper_events?(rest)
  def proper_events?(_), do: false

  @doc "True when no entry currently has the in-flight sent status."
  def no_sent?([]), do: true
  def no_sent?([{_, _, :sent} | _rest]), do: false
  def no_sent?([_entry | rest]), do: no_sent?(rest)
  def no_sent?(_), do: false

  @doc "Every previously terminal entry retains its exact key, amount and status."
  def terminal_preserved?({_, _, _, _, before}, {_, _, _, _, after_entries}),
    do: terminal_entries_preserved?(before, after_entries)

  def terminal_preserved?(_, _), do: false

  defp terminal_entries_preserved?([], _after), do: true

  defp terminal_entries_preserved?([{key, amount, status} | tail], after_entries) do
    if terminal?(status) do
      lookup(after_entries, key) == {:ok, {key, amount, status}} and
        terminal_entries_preserved?(tail, after_entries)
    else
      terminal_entries_preserved?(tail, after_entries)
    end
  end

  @doc "Independent replay oracle; a proper list of arbitrary events is required."
  def expected_run(state, []), do: state

  def expected_run(state, [event | rest]) do
    {next_state, _result, _effects} = expected_step(state, event)
    expected_run(next_state, rest)
  end

  @doc "Each intermediate independent-oracle authorization has an approval witness."
  def history_authorizations_explained?(_state, []), do: true

  def history_authorizations_explained?(state, [event | rest]) do
    {next_state, _result, _effects} = expected_step(state, event)

    authorized_only_on_result?(state, event, next_state) and
      history_authorizations_explained?(next_state, rest)
  end

  @doc "Independent composite invariant: exactly one obligation per voiding entry."
  def composite_valid?({ledger, obligations}) do
    valid?(ledger) and obligations_valid?(obligations, elem(ledger, 4), []) and
      all_voiding_present?(elem(ledger, 4), obligations)
  end

  def composite_valid?(_), do: false

  defp obligations_valid?([], _, _), do: true

  defp obligations_valid?([{key, count, outcome} | tail], entries, seen)
       when is_integer(key) and is_integer(count) and count >= 0 do
    not seen?(seen, key) and outcome_valid?(outcome) and
      voiding_entry?(lookup(entries, key)) and obligations_valid?(tail, entries, [key | seen])
  end

  defp obligations_valid?(_, _, _), do: false
  defp outcome_valid?(:unattempted), do: true

  defp outcome_valid?({:error, reason}),
    do:
      reason in [
        :unavailable,
        :not_found,
        :timeout,
        :declined,
        :adapter_error,
        :adapter_exception,
        :adapter_exit,
        :unexpected_reply,
        :uncertain,
        :task_start_failed,
        :capacity,
        :task_down
      ]

  defp outcome_valid?(_), do: false
  defp voiding_entry?({:ok, {_, _, :voiding}}), do: true
  defp voiding_entry?(_), do: false
  defp all_voiding_present?([], _), do: true

  defp all_voiding_present?([{key, _, :voiding} | tail], obligations),
    do: obligation_present?(obligations, key) and all_voiding_present?(tail, obligations)

  defp all_voiding_present?([_ | tail], obligations), do: all_voiding_present?(tail, obligations)
  defp obligation_present?([], _), do: false
  defp obligation_present?([{key, _, _} | _], key), do: true
  defp obligation_present?([_ | tail], key), do: obligation_present?(tail, key)

  @doc "Independent composite oracle; never calls production transition helpers."
  def expected_composite_step({ledger, obligations}, event) do
    {next, result, effects} = expected_step(ledger, event)

    updated =
      case {event, result} do
        {{:void, key}, :voiding} ->
          obligations ++ [{key, 0, :unattempted}]

        {{:void_confirmed, key}, :voided} ->
          expected_obligation_update(obligations, key, :remove)

        {{:void_attempt, key}, _} ->
          expected_obligation_update(obligations, key, :attempt)

        {{:void_outcome, key, {:error, _} = outcome}, _} ->
          if outcome_valid?(outcome),
            do: expected_obligation_update(obligations, key, {:outcome, outcome}),
            else: obligations

        {{:void_retry_enabled, key}, _} ->
          expected_obligation_update(obligations, key, :reset)

        _ ->
          obligations
      end

    {{next, updated}, result, effects}
  end

  @doc "Fold a proper finite history through the independent composite oracle."
  def expected_composite_run(state, []), do: state

  def expected_composite_run(state, [event | rest]) do
    {next, _, _} = expected_composite_step(state, event)
    expected_composite_run(next, rest)
  end

  defp expected_obligation_update([], _, _), do: []

  defp expected_obligation_update([{key, n, outcome} | rest], key, change) do
    case change do
      :remove -> rest
      :attempt -> [{key, n + 1, :unattempted} | rest]
      :reset -> [{key, 0, outcome} | rest]
      {:outcome, value} -> [{key, n, value} | rest]
    end
  end

  defp expected_obligation_update([entry | rest], key, change),
    do: [entry | expected_obligation_update(rest, key, change)]

  @doc "A previously issued identity remains capacity-holding in one of its post-dispatch states."
  def exposed_entry?({_, _, _, _, entries}, key, amount) do
    case lookup(entries, key) do
      {:ok, {^key, ^amount, status}} -> status in [:sent, :unknown, :authorized, :voiding]
      _ -> false
    end
  end

  def exposed_entry?(_, _, _), do: false

  @doc "The only trusted events that can release a previously issued key."
  def release_evidence?(event, key),
    do: event === {:processor_result, key, :declined} or event === {:void_confirmed, key}

  @doc "Independent reachable-pair relation for truthful environment deliveries."
  def exposure_valid?({{ledger, obligations}, {issued, records}}) do
    composite_valid?({ledger, obligations}) and
      issued_valid?(issued, elem(ledger, 4), []) and
      remote_valid?(records, issued, []) and
      local_remote_agree?(elem(ledger, 4), issued, records)
  end

  def exposure_valid?(_), do: false

  defp issued_valid?([], _, _), do: true

  defp issued_valid?([{key, amount, :issued} | rest], entries, seen)
       when is_integer(key) and is_integer(amount) and amount > 0 do
    not seen?(seen, key) and issued_local?(lookup(entries, key), amount) and
      issued_valid?(rest, entries, [key | seen])
  end

  defp issued_valid?(_, _, _), do: false

  defp issued_local?({:ok, {_, amount, status}}, amount),
    do: status in [:sent, :unknown, :authorized, :voiding, :declined, :voided]

  defp issued_local?(_, _), do: false

  defp remote_valid?([], _, _), do: true

  defp remote_valid?([{key, amount, status} | rest], issued, seen)
       when is_integer(key) and is_integer(amount) and amount > 0 and
              status in [:approved, :declined, :voided] do
    not seen?(seen, key) and lookup(issued, key) === {:ok, {key, amount, :issued}} and
      remote_valid?(rest, issued, [key | seen])
  end

  defp remote_valid?(_, _, _), do: false

  defp local_remote_agree?([], _, _), do: true

  defp local_remote_agree?([{key, amount, status} | rest], issued, records) do
    entry_agrees?(key, amount, status, lookup(issued, key), lookup(records, key)) and
      local_remote_agree?(rest, issued, records)
  end

  defp entry_agrees?(_, _, :reserved, :not_found, :not_found), do: true
  defp entry_agrees?(_, _, :voided, :not_found, :not_found), do: true

  defp entry_agrees?(key, amount, status, {:ok, {key, amount, :issued}}, observation) do
    case {status, observation} do
      {s, :not_found} when s in [:sent, :unknown] ->
        true

      {s, {:ok, {^key, ^amount, outcome}}}
      when s in [:sent, :unknown] and outcome in [:approved, :declined] ->
        true

      {:authorized, {:ok, {^key, ^amount, :approved}}} ->
        true

      {:voiding, {:ok, {^key, ^amount, outcome}}} when outcome in [:approved, :voided] ->
        true

      {:declined, {:ok, {^key, ^amount, :declined}}} ->
        true

      {:voided, {:ok, {^key, ^amount, :voided}}} ->
        true

      _ ->
        false
    end
  end

  defp entry_agrees?(_, _, _, _, _), do: false
end
