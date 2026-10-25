defmodule HoldLedger.Ledger do
  @moduledoc """
  Pure bounded authorization-hold reducer, implementing the ledger contract in the specification guide.

  Every state transition assumes a valid five-tuple with a proper, unique entry
  list. `step/2` accepts any *event* term and returns
  `{new_state, result_atom, effect_descriptions}` without executing effects.
  `run/2` accepts a proper finite list of events and throws away all effects.

  `init/2` is defined only for nonnegative integer limits; inputs outside that
  domain raise `FunctionClauseError`. The public event helpers have the same
  valid-state precondition as `step/2`. `find/2`, `set_status/3` and
  `mark_unknown/1` operate on the entry list; `set_status/3` assumes a known
  replacement status. This module performs no I/O or hidden state updates.
  """

  @type status :: :reserved | :sent | :unknown | :authorized | :declined | :voided
  @type entry :: {integer(), pos_integer(), status()}
  @type state ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer(), [entry()]}

  @doc "Create an empty ledger with both limits fixed."
  @spec init(non_neg_integer(), non_neg_integer()) :: state()
  def init(amount_limit, hold_limit)
      when is_integer(amount_limit) and amount_limit >= 0 and
             is_integer(hold_limit) and hold_limit >= 0 do
    {amount_limit, hold_limit, 0, 0, []}
  end

  @doc "Dispatch one arbitrary event against a valid state."
  @spec step(state(), term()) :: {state(), atom(), list()}
  def step(state, {:request, key, amount}), do: request(state, key, amount)
  def step(state, {:dispatch, key}), do: dispatch(state, key)
  def step(state, {:timeout, key}), do: timeout(state, key)
  def step(state, :restart), do: restart(state)
  def step(state, {:retry, key}), do: retry(state, key)
  def step(state, {:processor_result, key, outcome}), do: processor_result(state, key, outcome)
  def step(state, {:void, key}), do: void(state, key)
  def step(state, {:transport_ack, key}), do: transport_ack(state, key)
  def step(state, _), do: {state, :malformed, []}

  @doc "Replay a proper finite event list in order, discarding all effect data."
  @spec run(state(), list()) :: state()
  def run(state, []), do: state

  def run(state, [event | rest]) do
    {next_state, _result, _effects} = step(state, event)
    run(next_state, rest)
  end

  @doc "Find a key anywhere in the entries, including released terminal entries."
  def find([], _key), do: :not_found

  def find([{existing_key, _amount, _status} = entry | rest], key) do
    if existing_key == key, do: {:ok, entry}, else: find(rest, key)
  end

  @doc "Replace only the named entry's status, preserving every key and amount."
  def set_status([], _key, _status), do: []

  def set_status([{existing_key, amount, _old_status} | rest], key, status)
      when existing_key == key,
      do: [{existing_key, amount, status} | rest]

  def set_status([head | tail], key, status),
    do: [head | set_status(tail, key, status)]

  @doc "Convert every sent entry to unknown, leaving all other entries intact."
  def mark_unknown([]), do: []

  def mark_unknown([{key, amount, :sent} | rest]),
    do: [{key, amount, :unknown} | mark_unknown(rest)]

  def mark_unknown([head | tail]), do: [head | mark_unknown(tail)]

  @doc "Admit one positive fresh request if both independent limits permit it."
  def request({amount_limit, hold_limit, used_amount, used_holds, entries} = state, key, amount)
      when is_integer(key) and is_integer(amount) and amount > 0 do
    case find(entries, key) do
      {:ok, {_, ^amount, _}} ->
        {state, :duplicate, []}

      {:ok, _} ->
        {state, :conflict, []}

      :not_found ->
        cond do
          used_holds >= hold_limit ->
            {state, :insufficient_holds, []}

          amount > amount_limit - used_amount ->
            {state, :insufficient_amount, []}

          true ->
            {{amount_limit, hold_limit, used_amount + amount, used_holds + 1,
              [{key, amount, :reserved} | entries]}, :admitted, []}
        end
    end
  end

  def request(state, _key, _amount), do: {state, :malformed, []}

  @doc "Dispatch a reserved hold, producing an authorize intent with stored identity."
  def dispatch(
        {amount_limit, hold_limit, used_amount, used_holds, entries} = state,
        key
      )
      when is_integer(key) do
    case find(entries, key) do
      :not_found ->
        {state, :not_found, []}

      {:ok, {_, amount, :reserved}} ->
        {{amount_limit, hold_limit, used_amount, used_holds, set_status(entries, key, :sent)},
         :dispatched, [{:authorize, key, amount}]}

      _ ->
        {state, :stale, []}
    end
  end

  def dispatch(state, _), do: {state, :malformed, []}

  @doc "Record loss of certainty without releasing any capacity."
  def timeout(
        {amount_limit, hold_limit, used_amount, used_holds, entries} = state,
        key
      )
      when is_integer(key) do
    case find(entries, key) do
      :not_found ->
        {state, :not_found, []}

      {:ok, {_, _, :sent}} ->
        {{amount_limit, hold_limit, used_amount, used_holds, set_status(entries, key, :unknown)},
         :marked_unknown, []}

      _ ->
        {state, :stale, []}
    end
  end

  def timeout(state, _), do: {state, :malformed, []}

  @doc "After replay, every sent hold becomes unknown; other statuses are unaffected."
  def restart({amount_limit, hold_limit, used_amount, used_holds, entries}) do
    {{amount_limit, hold_limit, used_amount, used_holds, mark_unknown(entries)}, :restarted, []}
  end

  @doc "Retry an unknown operation using its stored key and amount."
  def retry(
        {amount_limit, hold_limit, used_amount, used_holds, entries} = state,
        key
      )
      when is_integer(key) do
    case find(entries, key) do
      :not_found ->
        {state, :not_found, []}

      {:ok, {_, amount, :unknown}} ->
        {{amount_limit, hold_limit, used_amount, used_holds, set_status(entries, key, :sent)},
         :retried, [{:authorize, key, amount}]}

      _ ->
        {state, :stale, []}
    end
  end

  def retry(state, _), do: {state, :malformed, []}

  @doc "Accept only processor approved/declined outcomes for sent or unknown."
  def processor_result(
        {amount_limit, hold_limit, used_amount, used_holds, entries} = state,
        key,
        outcome
      )
      when is_integer(key) and outcome in [:approved, :declined] do
    case find(entries, key) do
      :not_found ->
        {state, :not_found, []}

      {:ok, {_, amount, status}} when status in [:sent, :unknown] ->
        case outcome do
          :approved ->
            {{amount_limit, hold_limit, used_amount, used_holds,
              set_status(entries, key, :authorized)}, :authorized, []}

          :declined ->
            {{amount_limit, hold_limit, used_amount - amount, used_holds - 1,
              set_status(entries, key, :declined)}, :declined, []}
        end

      _ ->
        {state, :stale, []}
    end
  end

  def processor_result(state, _key, _outcome), do: {state, :malformed, []}

  @doc "Void reserved/authorized holds; only authorized needs a processor void intent."
  def void(
        {amount_limit, hold_limit, used_amount, used_holds, entries} = state,
        key
      )
      when is_integer(key) do
    case find(entries, key) do
      :not_found ->
        {state, :not_found, []}

      {:ok, {_, amount, :reserved}} ->
        {{amount_limit, hold_limit, used_amount - amount, used_holds - 1,
          set_status(entries, key, :voided)}, :voided, []}

      {:ok, {_, amount, :authorized}} ->
        {{amount_limit, hold_limit, used_amount - amount, used_holds - 1,
          set_status(entries, key, :voided)}, :voided, [{:void, key}]}

      _ ->
        {state, :stale, []}
    end
  end

  def void(state, _), do: {state, :malformed, []}

  @doc "A transport acknowledgment never establishes processor authorization."
  def transport_ack(state, key) when is_integer(key), do: {state, :stale, []}
  def transport_ack(state, _), do: {state, :malformed, []}
end
