# Reading deeper proofs

A ledger law may cite a shared theorem with a single `exact` line. Reviewing that law means following its predicates and the lemmas that connect them to the implementation. We’ll start with ledger validity, follow the admission and lookup proofs, then read a history relation to see which executions it covers.

Start here after you can read a `requires:`/`expects:` law and recognize a Lean hypothesis and goal. The [crash course](formal_verification_crash_course.md) introduces those ideas. You can inspect the source without running Lean; the runnable examples use the [pinned setup](getting-started.md) and files under `tmp/`.

## Open the predicate before trusting its name

The duplicate law assumes `Spec.valid?(s)`. Open `lib/hold_ledger/spec.ex` and follow that call through its helper:

```elixir
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
```

Read the checks in order. The outer function requires a five-field tuple and integer counters and limits. The helper excludes negative values. Its body then checks entry shape, unique keys, exact accounting and both capacity limits. A state can satisfy one of those conditions while violating another.

Follow `hold_amount/1` and `hold_count/1` to `holding?/1`. Reserved, sent, unknown, authorized and voiding entries consume capacity. Declined and voided entries remain in the list but do not contribute to either counter. A review of `valid?` therefore includes the status definitions and accounting functions it calls.

### Challenge a missing accounting clause

Suppose a proposed refactor deletes only `used_amount == hold_amount(entries)`. Which examples would still pass? Predict the result for a state with a 100-cent unknown hold but a zero used-amount counter.

Save this local comparison as `tmp/predicate_challenge.exs`. The copied predicate deliberately omits that clause; it leaves the repository's Spec unchanged.

```elixir
alias HoldLedger.Spec
import ExUnit.Assertions

weakened = fn
  {al, hl, ua, uh, entries}
  when is_integer(al) and is_integer(hl) and is_integer(ua) and is_integer(uh) and
         al >= 0 and hl >= 0 and ua >= 0 and uh >= 0 ->
    Spec.proper_entries?(entries) and Spec.unique_keys?(entries) and
      uh == Spec.hold_count(entries) and ua <= al and uh <= hl

  _ ->
    false
end

empty = {100, 2, 0, 0, []}
held = {100, 2, 100, 1, [{1, 100, :unknown}]}
wrong_total = {100, 2, 0, 1, [{1, 100, :unknown}]}

# Both predicates accept these valid states.
assert Spec.valid?(empty) and weakened.(empty)
assert Spec.valid?(held) and weakened.(held)

# The incorrect counter exposes the omitted guarantee.
assert Spec.hold_amount(elem(wrong_total, 4)) == 100
refute Spec.valid?(wrong_total)
assert weakened.(wrong_total)
```

Run `uv run --locked python scripts/local_run.py mix run tmp/predicate_challenge.exs`. All assertions pass: the last pair demonstrates the disagreement. Tests checking only `empty` and `held` would stay green under the weakened predicate.

If a theorem concludes this weaker predicate, it promises less. If it assumes the predicate, it must handle more inputs. Neither change is a proof-body repair. Use the [review rules](human_review.md#classify-the-diff) before accepting either one. This experiment checks concrete cases; it does not prove that every law using the changed predicate would still pass.

## Follow the admission proof

The toy `fits/2` law checks one amount boundary. PO-A2 adds a valid ledger, a fresh integer key, a positive amount and an available slot. Its precondition is `Spec.request_eligible?/3`; open that function immediately below `valid?/1`. Its last comparison uses `<=`, so an exact amount fit is eligible.

Try the boundary case in `iex -S mix`:

```elixir
alias HoldLedger.{Ledger, Spec}
s = {100, 1, 0, 0, []}
true = Spec.request_eligible?(s, 11, 100)
{{100, 1, 100, 1, [{11, 100, :reserved}]}, :admitted, []} =
  Ledger.request(s, 11, 100)
```

Now read `test/laws/po_a2_test.exs`. The conclusion requires both the exact updated tuple and equality with `Spec.expected_step/2`. A valid state alone would not require admission. The law delegates its proof to `«po_a2/3»` in `test/support/lean/Request.lean`.

Read this opening excerpt alongside the complete theorem in `Request.lean`:

```lean
  have compatible := HoldLedgerProof.compatible_1
  have totals := HoldLedgerProof.totals_1
  cases key <;>
    simp_all [«po_a2:requires/3», Elixir.HoldLedger.Spec.«request_eligible?/3»,
      Erlang.erlang.«is_integer/1», Lynx.Term.true, Lynx.Term.false]
  all_goals cases amount <;>
    simp_all []
  all_goals repeat' (split at requires <;> try simp_all [])
  all_goals simp [Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
      bind, Except.bind] at requires
  all_goals repeat' (split at requires <;> try simp_all [])
```

At entry, `requires` says that the translated eligibility predicate returned true; the goal says that the translated postcondition must return true. The two `have` lines bring lookup compatibility and accounting facts into scope. `cases key` and `cases amount` consider the possible Elixir-term constructors. Simplification closes the noninteger cases because eligibility excludes them. `split at requires` separates branches of the translated checks.

The proof then opens validity and uses the accounting lemma to obtain integer totals. Track the facts each stage supplies and the goal they support:

| Point in the argument | Facts available | What remains to show |
|---|---|---|
| Eligibility opened | Valid state, integer key, positive amount, fresh key, room under both limits | The request must take the admission branch |
| Validity opened | Proper entries, unique keys, counters equal entry totals | The implementation and reference lookups agree |
| Lookups connected | Both lookups report that the key is absent | Admission builds the required tuple and matches the oracle |
| Admission unfolded | The new reserved entry contributes its amount and one slot | The two accounting expressions agree |

The table describes the argument in ordinary language. The Lean source expresses these facts through translated terms. Its lookup bridge reads:

```lean
  have find_eq : ∀ es k, Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
      Elixir.HoldLedger.Ledger.«find/2» es k = Elixir.HoldLedger.Spec.«lookup/2» es k := by
    intro es k hp
    obtain ⟨v, hf, hl⟩ := compatible es k hp
    exact hf.trans hl.symm
```

`compatible` gives a value `v` that both lookups return. `hf.trans hl.symm` reverses the reference equality and joins the two equalities, proving that the lookups agree. The final simplification opens `Ledger.request`, the reference transition and the accounting functions. The concluding `omega` calls prove the remaining arithmetic goals.

To attempt this group alone, run:

```sh
uv run --locked python scripts/run_laws.py --slug po_a2 --stage proofs \
  --report tmp/verification/po_a2-reading.json
```

Before running it, explain why changing the admission comparison from `>` to `>=` would reject the witness above. The proof's job is to establish the existing claim; changing its precondition to exclude exact fits would remove required behavior.

## Follow lookup through a list

Admission needs to establish that a key is absent. Duplicate handling needs to establish that a key is present. Both rely on agreement between `Ledger.find/2` and `Spec.lookup/2`. Open `test/support/lean/Lookup.lean` at `«po_a4_duplicate/4»`, the theorem used in the [crash course](formal_verification_crash_course.md#read-a-ledger-law).

The theorem derives this shape fact from validity:

```lean
have shaped : ∀ s, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
    ∃ al hl ua uh es, s = Lynx.Term.tuple #[al, hl, ua, uh, es] ∧
      Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true := by
```

It says: if the specification judges a state valid, then that state can be unpacked into five fields and its entries form a proper list. The proof then uses the compatibility lemma to connect the reference lookup with the implementation's lookup, and simplifies the duplicate-request branch.

The compatibility lemmas depend on reasoning over lists. To see how **induction** works, save this native Lean example as `tmp/append_empty.lean`:

```lean
import Lean

theorem append_empty (xs : List Nat) : xs ++ [] = xs := by
  induction xs with
  | nil => rfl
  | cons head tail ih =>
      change head :: (tail ++ []) = head :: tail
      rw [ih]
```

Run `uv run --locked python scripts/local_run.py lean tmp/append_empty.lean`. Success exits with status zero and no output.

The `nil` case handles the empty list. In the `cons` case, `ih` is the **inductive hypothesis**: appending `[]` leaves the shorter tail unchanged. `change` exposes the recursive append on the tail; `rw [ih]` replaces `tail ++ []` with `tail`, making the two sides equal. `test/support/lean/CoreLookup.lean` uses `fun_induction Elixir.HoldLedger.Spec.«lookup/2» es k` to follow the recursive branches of the translated lookup function. That is functional induction: its cases and inductive hypotheses come from the function’s recursion, rather than directly from the `nil` and `cons` constructors of a native list.

The shared theorem connects independently implemented lookups over proper entry lists. Check that assumption before reusing the theorem for another state domain.

## Read data types and execution relations

A lookup proof follows recursion over entries. A history proof follows the constructors that define an allowed execution. To read that proof, first distinguish a data type from a relation about data.

A Lean `structure` has named fields. An `inductive` definition lists constructors that build its values. For example:

```lean
structure ToyHold where
  key : Int
  amount : Nat

inductive ToyOutcome where
  | unknown
  | approved
  | declined
```

`ToyOutcome` has three alternatives, each with no fields. An inductive **relation** goes further: its constructors can require facts about the values being related. Save this history of successful additions as `tmp/toy_run.lean`:

```lean
import Lean

def toyStep (state amount : Nat) : Option Nat :=
  if amount = 0 then none else some (state + amount)

inductive ToyRun : Nat → List Nat → Nat → Prop where
  | empty (state) : ToyRun state [] state
  | next {state amount nextState amounts final} :
      toyStep state amount = some nextState →
      ToyRun nextState amounts final →
      ToyRun state (amount :: amounts) final

example : ToyRun 0 [2] 2 :=
  ToyRun.next rfl (ToyRun.empty 2)
```

Run `uv run --locked python scripts/local_run.py lean tmp/toy_run.lean`. It checks both the relation and the one-step example.

`ToyRun state amounts final` says the listed amounts take the initial state to the final one. `empty` admits an empty history with unchanged state. `next` needs two facts: the first step succeeds, and the remaining history runs from that step's result to `final`. In the example, `rfl` checks the first step by evaluation and `ToyRun.empty 2` supplies the empty tail.

**Checkpoint:** does this relation admit `[2, 0]` from state `0`? Does any constructor mention disk? The zero step returns `none`, so no `next` constructor can supply its success premise. No constructor records a write or flush; a proof about `ToyRun` cannot establish storage durability.

The production relation `Committed` in `test/support/lean/Recovery.lean` follows the same pattern. Its `next` constructor requires a translated `Composite.step/2` result wrapped in `Except.ok`, followed by a committed tail. That result may describe a rejected ledger operation: `Except.ok` means evaluation succeeded. The states and events are `Lynx.Term` values, while the history itself is a native Lean list.

## Decide what the proof leaves to the runtime

The name `Committed` invites a question about persistence. Its constructors let us answer precisely: what evidence must exist before a history counts as committed?

As a final exercise, open `test/support/lean/Recovery.lean` and answer:

1. What does `Committed.empty` say about the initial and final states?
2. Which result must `Composite.step/2` return for `Committed.next` to apply?
3. Where would a disk-sync guarantee have to enter the argument? Is it present?

<details>
<summary>Answers — open after reading the constructors</summary>

The empty history has the same initial and final state. The next constructor requires `Except.ok` containing the next state, result and effects, plus a committed tail. Those premises describe translated evaluation. They contain no journal write, flush or restart operation. A disk guarantee would require a separate connection between the runtime's persistence behavior and this model.

</details>

Continue with the [assurance audit](audit.md#lean-execution-relations-examine-what-a-history-means) to inspect that connection and its external assumptions. For a proposed code or proof change, use [Human review](human_review.md) to classify the diff and check the evidence for the exact source under review.
