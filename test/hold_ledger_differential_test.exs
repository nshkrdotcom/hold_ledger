defmodule HoldLedger.DifferentialTest do
  use ExUnit.Case, async: true
  alias HoldLedger.Differential

  test "model samples cover completion, tombstones, lifecycle retirement and coupled validity" do
    cases = Differential.model_cases(32)

    for module <- [
          HoldLedger.Attempts,
          HoldLedger.Composite,
          HoldLedger.Environment,
          HoldLedger.Exposure,
          HoldLedger.Spec
        ] do
      assert Enum.any?(cases, fn {target, _, _} -> target == module end)
    end

    assert Enum.any?(cases, fn
             {HoldLedger.Attempts, :step, [_, {:shutdown_result, _}]} -> true
             _ -> false
           end)

    assert Enum.any?(cases, fn
             {HoldLedger.Exposure, :step, [_, {:confirm, _}]} -> true
             _ -> false
           end)

    assert Enum.any?(cases, fn
             {HoldLedger.Environment, :deliver,
              [{_, [{1, 0, :voided}]}, {:authorize, 1, :approved}]} ->
               true

             _ ->
               false
           end)

    assert Enum.all?(cases, fn {module, function, args} ->
             match?({:ok, _}, Differential.result(module, function, args))
           end)
  end

  test "wire golden vectors preserve type, atom names and nesting" do
    vectors = [
      {1, ["integer", "1"]},
      {1.0, ["float", "4607182418800017408"]},
      {-0.0, ["float", "9223372036854775808"]},
      {:approved, ["atom", "approved"]},
      {{1, []}, ["tuple", [["integer", "1"], ["list", []]]]}
    ]

    for {value, wire} <- vectors do
      assert Differential.encode(value) == wire
      assert Differential.encode(Differential.decode(wire)) == wire
      assert Differential.decode(Differential.encode(value)) === value
    end
  end

  test "wire rejects malformed, unsupported and unbounded atom inputs" do
    for wire <- [
          ["unknown", "1"],
          ["integer", "1.0"],
          ["tuple", 4],
          ["atom", "never_created_atom_for_hold_ledger_729188"],
          ["float", "-1"],
          ["float", "18446744073709551616"],
          ["float", "9218868437227405312"]
        ] do
      assert_raise ArgumentError, fn -> Differential.decode(wire) end
    end

    assert_raise ArgumentError, fn -> Differential.encode(self()) end
    assert_raise ArgumentError, fn -> Differential.encode(%{}) end
  end

  test "mismatch minimization retains an actual witness with a bounded evaluator budget" do
    {minimal, attempts} =
      Differential.minimize(
        [100, [:approved, 32]],
        fn
          [n, _] -> is_integer(n) and n >= 3
        end,
        40
      )

    assert hd(minimal) >= 3
    assert hd(minimal) < 100
    assert attempts <= 40

    assert {[1.0], 1} == Differential.minimize([1.0], fn _ -> false end, 1)
    assert {[1], 0} == Differential.minimize([1], fn _ -> flunk("budget exhausted") end, 0)
  end
end
