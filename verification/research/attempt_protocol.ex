defmodule HoldLedger.Verification.AttemptProtocol do
  @moduledoc """
  Research-only closed protocol abstraction for Phase 3 (0300-05).

  This is NOT a model of GenServer, a disk, a processor, OTP scheduling or
  the Ledger/Spec business state. One owner serializes lifecycle events. The
  environment supplies attempt-ID-tagged results. `persist_ok` is admissible
  only after a successful Journal.append_sync/2 acknowledgment; `persist_error`
  poisons the owner and MUST NOT free its occupied slot. No fairness, delivery,
  timing, or remote non-resurrection guarantees are assumed.

  `project/1` relates this model to HoldLedger.Attempts' tuple on admitted
  events. `source_event/2` translates abstract persistence acknowledgments
  to Attempts' `{:committed, id}`; it is not a claim that Attempts validates
  actual journal acknowledgments. Server must enforce that boundary.

  Search is finite and always reports its depth; it is not an unbounded proof.
  Deliberately wrong variants must yield complete counterexamples.
  """

  alias HoldLedger.Attempts

  defstruct next: 1,
            poisoned?: false,
            active: [],
            pending: MapSet.new(),
            synced: MapSet.new(),
            retired: MapSet.new(),
            stale_commits: MapSet.new()

  def init, do: %__MODULE__{}

  def project(%__MODULE__{next: next, poisoned?: poisoned?, active: active}),
    do: {next, poisoned?, active}

  defp entry(entries, id), do: Enum.find(entries, &(elem(&1, 0) == id))

  defp occupied?(entries, kind, key),
    do: Enum.any?(entries, fn {_, k, q, _} -> k == kind and q == key end)

  defp update_phase(entries, id, phase) do
    Enum.map(entries, fn
      {^id, kind, key, _} -> {id, kind, key, phase}
      other -> other
    end)
  end

  @doc "Pure environment step; the :correct variant is the only intended model."
  def step(state, event, variant \\ :correct)

  def step(%__MODULE__{} = state, {:start, kind, key, limit}, _variant)
      when kind in [:authorize, :void, :lookup] and is_integer(key) and
             is_integer(limit) and limit > 0 do
    if not state.poisoned? and length(state.active) < limit and
         not occupied?(state.active, kind, key) do
      %{state | next: state.next + 1,
                active: [{state.next, kind, key, :running} | state.active]}
    else
      state
    end
  end

  def step(%__MODULE__{} = state, {:result, id}, :retire_before_sync) do
    case entry(state.active, id) do
      {^id, _, _, :running} ->
        %{state | active: Enum.reject(state.active, &(elem(&1, 0) == id)),
                  retired: MapSet.put(state.retired, id)}

      _ -> state
    end
  end

  def step(%__MODULE__{} = state, {:late_result, id}, :accept_retired_result) do
    if MapSet.member?(state.retired, id) do
      %{state | stale_commits: MapSet.put(state.stale_commits, id)}
    else
      step(state, {:result, id})
    end
  end

  def step(%__MODULE__{} = state, {:late_result, id}, _variant),
    do: step(state, {:result, id})

  def step(%__MODULE__{} = state, {:deadline, id}, _variant),
    do: transition(state, id, :running, :stopping, false)

  def step(%__MODULE__{} = state, {:result, id}, _variant),
    do: transition(state, id, :running, :committing, true)

  def step(%__MODULE__{} = state, {:down, id}, _variant),
    do: transition(state, id, :running, :committing, true)

  def step(%__MODULE__{} = state, {:shutdown_result, id}, _variant),
    do: transition(state, id, :stopping, :committing, true)

  def step(%__MODULE__{} = state, {:persist_ok, id}, _variant) do
    if not state.poisoned? and MapSet.member?(state.pending, id) and
         match?({^id, _, _, :committing}, entry(state.active, id)) do
      %{state | active: Enum.reject(state.active, &(elem(&1, 0) == id)),
                pending: MapSet.delete(state.pending, id),
                synced: MapSet.put(state.synced, id),
                retired: MapSet.put(state.retired, id)}
    else
      state
    end
  end

  def step(%__MODULE__{} = state, {:persist_error, id}, _variant) do
    if MapSet.member?(state.pending, id) and match?({^id, _, _, :committing}, entry(state.active, id)) do
      %{state | poisoned?: true}
    else
      state
    end
  end

  def step(%__MODULE__{} = state, :poison, _variant), do: %{state | poisoned?: true}
  def step(%__MODULE__{} = state, _, _variant), do: state

  defp transition(state, id, from, to, needs_sync?) do
    case entry(state.active, id) do
      {^id, _, _, ^from} ->
        %{state | active: update_phase(state.active, id, to),
                  pending: if(needs_sync?, do: MapSet.put(state.pending, id), else: state.pending)}

      _ -> state
    end
  end

  @doc "Translate only admissible environment steps to source Attempts.step/2."
  def source_event(state, {:persist_ok, id}) do
    if not state.poisoned? and MapSet.member?(state.pending, id),
      do: {:committed, id},
      else: :unadmitted
  end

  def source_event(state, {:persist_error, id}) do
    if MapSet.member?(state.pending, id), do: :poison, else: :unadmitted
  end

  def source_event(_state, {:late_result, id}), do: {:result, id}
  def source_event(_state, event), do: event

  def source_step_agrees?(state, event) do
    actual = state |> project() |> Attempts.step(source_event(state, event)) |> elem(0)
    actual == (state |> step(event) |> project())
  end

  @doc "A safety predicate on the explicit, finite abstract state only."
  def safe?(%__MODULE__{} = s) do
    ids = Enum.map(s.active, &elem(&1, 0))
    slots = Enum.map(s.active, fn {_, kind, key, _} -> {kind, key} end)
    all_ids = MapSet.new(ids)

    length(ids) == length(Enum.uniq(ids)) and
      length(slots) == length(Enum.uniq(slots)) and
      Enum.all?(s.active, fn {id, kind, key, phase} ->
        is_integer(id) and id > 0 and id < s.next and is_integer(key) and
          kind in [:authorize, :void, :lookup] and
          phase in [:running, :stopping, :committing]
      end) and
      Enum.all?(s.pending, fn id ->
        match?({^id, _, _, :committing}, entry(s.active, id))
      end) and
      MapSet.disjoint?(all_ids, s.retired) and
      MapSet.subset?(s.retired, s.synced) and
      MapSet.size(s.stale_commits) == 0
  end

  @doc "All enabled environment choices for two attempt IDs on one key."
  def choices(s) do
    starts = if s.next <= 2, do: [{:start, :authorize, 7, 1}], else: []
    ids = Enum.map(s.active, &elem(&1, 0)) ++ Enum.sort(MapSet.to_list(s.retired))

    starts ++
      Enum.flat_map(ids, fn id ->
        for tag <- [:result, :down, :deadline, :shutdown_result, :persist_ok,
                    :persist_error, :late_result], do: {tag, id}
      end) ++ [:poison]
  end

  @doc """
  Exhaustively explores unique states through the given finite depth.
  A `:bounded` return means only no violation *within that bound*; never
  infer unbounded safety or scheduler completeness from it. A resource limit
  is an unresolved result, not a green check.
  """
  def bounded(depth, variant \\ :correct, max_states \\ 20_000)
      when is_integer(depth) and depth > 0 and is_integer(max_states) and max_states > 0 do
    explore(:queue.from_list([{init(), []}]), MapSet.new([init()]), depth, variant, max_states)
  end

  defp explore(queue, seen, depth, variant, limit) do
    case :queue.out(queue) do
      {:empty, _} ->
        {:bounded, %{depth: depth, states: MapSet.size(seen), truncated_at_depth: true}}

      {{:value, {_state, trace}}, rest} when length(trace) >= depth ->
        explore(rest, seen, depth, variant, limit)

      {{:value, {state, trace}}, rest} ->
        Enum.reduce_while(choices(state), {rest, seen}, fn event, {waiting, found} ->
          next = step(state, event, variant)
          next_trace = trace ++ [event]

          cond do
            not safe?(next) ->
              {:halt, {:counterexample, next_trace, %{event: event, state: next}}}

            variant == :correct and not source_step_agrees?(state, event) ->
              {:halt, {:refinement_mismatch, next_trace, %{event: event, state: next}}}

            MapSet.member?(found, next) ->
              {:cont, {waiting, found}}

            MapSet.size(found) >= limit ->
              {:halt, {:resource_limit, %{depth: depth, states: MapSet.size(found)}}}

            true ->
              {:cont, {:queue.in({next, next_trace}, waiting), MapSet.put(found, next)}}
          end
        end)
        |> case do
          {waiting, found} -> explore(waiting, found, depth, variant, limit)
          violation -> violation
        end
    end
  end
end
