defmodule HoldLedger.EnvironmentTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Environment, Ledger, Spec}

  test "void before authorize installs a permanent terminal fence" do
    state = Environment.issue(Environment.init(), {:authorize, 1, 100})
    {state, :void_confirmed} = Environment.deliver(state, {:void, 1})
    assert {^state, :declined} = Environment.deliver(state, {:authorize, 1, :approved})
    assert {^state, :void_confirmed} = Environment.deliver(state, {:void, 1})
  end

  test "unissued authorizations cannot become live" do
    initial = Environment.init()
    assert {^initial, :not_issued} = Environment.deliver(initial, {:authorize, 2, :approved})
  end

  test "purging a terminal fence permits resurrection and violates the environment hypothesis" do
    remote = Environment.issue(Environment.init(), {:authorize, 1, 100})
    {terminal, :void_confirmed} = Environment.deliver(remote, {:void, 1})
    ledger = {100, 1, 0, 0, [{1, 100, :voided}]}
    assert Spec.valid?(ledger)
    assert Environment.covered?(terminal, ledger)

    # Simulate loss/expiry of processor records while delayed requests remain.
    forgotten = {elem(terminal, 0), []}
    {resurrected, :approved} = Environment.deliver(forgotten, {:authorize, 1, :approved})
    refute Environment.covered?(resurrected, ledger)
    assert {^terminal, :declined} = Environment.deliver(terminal, {:authorize, 1, :approved})
  end

  test "a false decline releases local capacity while the remote remains live" do
    remote = Environment.issue(Environment.init(), {:authorize, 1, 100})
    {remote, :approved} = Environment.deliver(remote, {:authorize, 1, :approved})
    sent = {100, 1, 100, 1, [{1, 100, :sent}]}
    {ledger, :declined, []} = Ledger.step(sent, {:processor_result, 1, :declined})
    assert Spec.valid?(ledger)
    refute Environment.covered?(remote, ledger)
  end
end
