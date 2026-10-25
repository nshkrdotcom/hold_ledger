defmodule HoldLedger.TransitionTest do
  use ExUnit.Case, async: true

  alias HoldLedger.{Ledger, Spec, TestFixtures}

  @statuses [:reserved, :sent, :unknown, :authorized, :declined, :voided]

  test "init validates its advertised domain; zero limits admit nothing" do
    assert Ledger.init(0, 0) == {0, 0, 0, 0, []}
    assert Spec.valid?(Ledger.init(0, 0))

    assert Ledger.step(TestFixtures.zero(), {:request, 1, 1}) ==
             {TestFixtures.zero(), :insufficient_holds, []}

    assert_raise FunctionClauseError, fn -> Ledger.init(-1, 1) end
    assert_raise FunctionClauseError, fn -> Ledger.init(1, :unbounded) end
  end

  test "fresh exact-fit admission prepends one reserved entry and increments both counters" do
    s = TestFixtures.exact_fit()

    assert Ledger.step(s, {:request, 11, 100}) ==
             {{100, 1, 100, 1, [{11, 100, :reserved}]}, :admitted, []}

    assert Ledger.step(TestFixtures.empty(), {:request, -7, 1}) ==
             {{1000, 3, 1, 1, [{-7, 1, :reserved}]}, :admitted, []}
  end

  test "hold cap, amount cap and simultaneous failure precedence" do
    assert Ledger.step(TestFixtures.full_slots(), {:request, 22, 1}) ==
             {TestFixtures.full_slots(), :insufficient_holds, []}

    assert Ledger.step(TestFixtures.full_amount(), {:request, 22, 1}) ==
             {TestFixtures.full_amount(), :insufficient_amount, []}

    assert Ledger.step(TestFixtures.full_both(), {:request, 22, 1}) ==
             {TestFixtures.full_both(), :insufficient_holds, []}

    assert Ledger.step(TestFixtures.empty(), {:request, 22, 1001}) ==
             {TestFixtures.empty(), :insufficient_amount, []}
  end

  for status <- @statuses do
    test "same and conflicting duplicate key in #{status}, including terminal history" do
      s = TestFixtures.with_status(unquote(status))
      assert Spec.valid?(s)
      assert Ledger.step(s, {:request, 11, 300}) == {s, :duplicate, []}
      assert Ledger.step(s, {:request, 11, 301}) == {s, :conflict, []}
    end
  end

  test "dispatch only reserved: original amount in authorize intent" do
    assert Ledger.step(TestFixtures.reserved(), {:dispatch, 11}) ==
             {TestFixtures.sent(), :dispatched, [{:authorize, 11, 300}]}
  end

  test "timeout retains unknown capacity; unrelated new requests can increase counters" do
    assert Ledger.step(TestFixtures.sent(), {:timeout, 11}) ==
             {TestFixtures.unknown(), :marked_unknown, []}

    assert Ledger.step(TestFixtures.unknown(), {:request, 22, 200}) ==
             {{1000, 3, 500, 2, [{22, 200, :reserved}, {11, 300, :unknown}]}, :admitted, []}
  end

  test "retry reuses the original unknown key and stored amount" do
    assert Ledger.step(TestFixtures.unknown(), {:retry, 11}) ==
             {TestFixtures.sent(), :retried, [{:authorize, 11, 300}]}
  end

  for state <- [:sent, :unknown] do
    test "approved and declined results from #{state} release only on decline" do
      s = TestFixtures.with_status(unquote(state))

      assert Ledger.step(s, {:processor_result, 11, :approved}) ==
               {TestFixtures.authorized(), :authorized, []}

      assert Ledger.step(s, {:processor_result, 11, :declined}) ==
               {TestFixtures.declined(), :declined, []}
    end
  end

  test "ack never counts as processor authorization, including missing keys" do
    for s <- TestFixtures.all() do
      assert Ledger.step(s, {:transport_ack, 11}) == {s, :stale, []}
      assert Ledger.step(s, {:transport_ack, 99}) == {s, :stale, []}
    end
  end

  test "void reserved emits nothing; void authorized emits a single void intent" do
    assert Ledger.step(TestFixtures.reserved(), {:void, 11}) ==
             {TestFixtures.voided(), :voided, []}

    assert Ledger.step(TestFixtures.authorized(), {:void, 11}) ==
             {TestFixtures.voided(), :voided, [{:void, 11}]}

    assert Ledger.step(TestFixtures.sent(), {:void, 11}) ==
             {TestFixtures.sent(), :stale, []}

    assert Ledger.step(TestFixtures.unknown(), {:void, 11}) ==
             {TestFixtures.unknown(), :stale, []}
  end

  test "restart converts all sent entries, and ONLY sent entries, to unknown" do
    assert Ledger.step(TestFixtures.mixed(), :restart) ==
             {{1000, 4, 700, 3,
               [
                 {11, 300, :unknown},
                 {12, 200, :unknown},
                 {13, 200, :authorized},
                 {14, 100, :declined},
                 {15, 100, :voided}
               ]}, :restarted, []}

    assert Ledger.step(TestFixtures.zero(), :restart) ==
             {TestFixtures.zero(), :restarted, []}
  end

  test "valid missing-key events return not_found; ineligible existing key returns stale" do
    for {tag, key} <- [dispatch: 99, timeout: 99, retry: 99, void: 99] do
      assert Ledger.step(TestFixtures.unknown(), {tag, key}) ==
               {TestFixtures.unknown(), :not_found, []}
    end

    for outcome <- [:approved, :declined] do
      assert Ledger.step(TestFixtures.reserved(), {:processor_result, 99, outcome}) ==
               {TestFixtures.reserved(), :not_found, []}
    end
  end

  for status <- @statuses do
    test "all wrong-state branch results in #{status} match explicit table" do
      s = TestFixtures.with_status(unquote(status))

      expected = %{
        reserved: %{
          dispatch: :dispatched,
          timeout: :stale,
          retry: :stale,
          approved: :stale,
          declined: :stale,
          void: :voided
        },
        sent: %{
          dispatch: :stale,
          timeout: :marked_unknown,
          retry: :stale,
          approved: :authorized,
          declined: :declined,
          void: :stale
        },
        unknown: %{
          dispatch: :stale,
          timeout: :stale,
          retry: :retried,
          approved: :authorized,
          declined: :declined,
          void: :stale
        },
        authorized: %{
          dispatch: :stale,
          timeout: :stale,
          retry: :stale,
          approved: :stale,
          declined: :stale,
          void: :voided
        },
        declined: %{
          dispatch: :stale,
          timeout: :stale,
          retry: :stale,
          approved: :stale,
          declined: :stale,
          void: :stale
        },
        voided: %{
          dispatch: :stale,
          timeout: :stale,
          retry: :stale,
          approved: :stale,
          declined: :stale,
          void: :stale
        }
      }

      events = [
        {:dispatch, 11},
        {:timeout, 11},
        {:retry, 11},
        {:processor_result, 11, :approved},
        {:processor_result, 11, :declined},
        {:void, 11}
      ]

      for {event, result} <-
            Enum.zip(events, [
              expected[unquote(status)].dispatch,
              expected[unquote(status)].timeout,
              expected[unquote(status)].retry,
              expected[unquote(status)].approved,
              expected[unquote(status)].declined,
              expected[unquote(status)].void
            ]) do
        assert {_, ^result, _} = Ledger.step(s, event)
      end
    end
  end

  test "ill-formed events are malformed before lookup, including improper terms" do
    events = [
      nil,
      1,
      :dispatch,
      {},
      [],
      [1 | :not_a_list],
      {:request, 11, 0},
      {:request, 11, -1},
      {:request, 11, 1.0},
      {:request, :bad, 10},
      {:dispatch, "11"},
      {:timeout, nil},
      {:retry, 1.5},
      {:void, 1.2},
      {:processor_result, 11, :unknown},
      {:processor_result, 11, :approved, :extra},
      {:processor_result, :bad, :approved},
      {:transport_ack, :bad},
      {:request, 11, 300, :extra},
      {:restart},
      :not_a_command
    ]

    for s <- [TestFixtures.unknown(), TestFixtures.empty()], e <- events do
      assert Ledger.step(s, e) == {s, :malformed, []}
    end
  end

  test "find, status replacement, global sent-to-unknown recursion and run are pure" do
    entries = elem(TestFixtures.mixed(), 4)
    assert Ledger.find(entries, 12) == {:ok, {12, 200, :unknown}}
    assert Ledger.find(entries, 99) == :not_found

    assert Ledger.set_status(entries, 11, :unknown) ==
             [{11, 300, :unknown} | tl(entries)]

    assert Ledger.set_status(entries, 99, :sent) == entries

    assert Ledger.mark_unknown(entries) ==
             [{11, 300, :unknown} | tl(entries)]

    s = TestFixtures.empty()
    assert Ledger.run(s, []) == s

    assert Ledger.run(s, [{:request, 22, 100}, {:dispatch, 22}, :restart]) ==
             {1000, 3, 100, 1, [{22, 100, :unknown}]}
  end
end
