defmodule HoldLedgerReviewWeb.ExplainTest do
  use ExUnit.Case, async: true
  alias HoldLedgerReview.Adversarial
  alias HoldLedgerReviewWeb.Explain

  test "the eight starting alternatives describe their distinguishing behavior" do
    expectations = %{
      "P01" => ["0¢ of 100¢", "cancelled", "No outside work requested"],
      "P02" => ["100¢ of 100¢", "cancellation pending", "No outside work requested"],
      "P03" => ["Hold declined", "0¢ of 100¢"],
      "P04" => ["refused for insufficient amount", "No recorded holds"],
      "P05" => ["0¢ of 100¢", "Requests remote cancellation"],
      "P06" => ["0¢ of 100¢", "unknown"],
      "P07" => ["100¢ of 250¢", "Hold 1 (50¢): cancelled", "Hold 2 (100¢): unknown"],
      "P08" => ["0¢ of 100¢", "Hold cancelled", "No outside work requested"]
    }

    for {id, fragments} <- expectations do
      {:ok, witness} = Adversarial.seed(id)
      text = Explain.output(witness["output"])
      for fragment <- fragments, do: assert(text =~ fragment, id <> ": " <> text)
      assert Explain.state(witness["before"]) =~ "reserved"
      refute Explain.event(witness["event"]) =~ "not described"
    end
  end

  test "empty, multiple and unfamiliar entries remain explicit without inventing meaning" do
    empty = %{
      "amount_limit" => 100,
      "hold_limit" => 2,
      "used_amount" => 0,
      "used_holds" => 0,
      "entries" => []
    }

    assert Explain.state(empty) =~ "No recorded holds"

    state = %{
      empty
      | "entries" => [
          %{"key" => 1, "amount" => 10, "status" => "unknown"},
          %{"key" => 2, "amount" => 20, "status" => "invented"}
        ]
    }

    assert Explain.state(state) =~ "Hold 1 (10¢): unknown"
    assert Explain.state(state) =~ "unrecognized status"
    refute Explain.state(state) =~ "invented"
    assert Explain.state(nil) =~ "unavailable"
    assert Explain.event(%{"type" => "invented"}) =~ "not described"
    assert Explain.output(nil) =~ "unavailable"
  end

  test "effects describe requested work without claiming it completed" do
    {:ok, seed} = Adversarial.seed("P01")

    output = %{
      seed["output"]
      | "effects" => [
          %{"type" => "authorize", "key" => 3, "amount" => 25},
          %{"type" => "void", "key" => 1, "amount" => nil}
        ]
    }

    text = Explain.output(output)
    assert text =~ "Requests authorization of hold 3 for 25¢"
    assert text =~ "does not confirm approval"
    assert text =~ "does not confirm cancellation"
  end
end
