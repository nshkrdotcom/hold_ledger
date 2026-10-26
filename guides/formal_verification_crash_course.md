# Formal Verification Crash Course: From Tests to Proofs

This guide assumes you write Elixir and use unit and property tests. It introduces Lean through a complete arithmetic proof, then follows a duplicate-request law from its Elixir contract into the shared Lean proof.

You will need the [toolchain setup](getting-started.md) to run the examples. Blocks marked as excerpts or pseudocode omit details; the law files and shared Lean theory contain the executable repository proofs.

---

## 1. What Tests and Proofs Establish

Tests and proofs answer different questions. A concrete test checks an execution; a generated test explores executions chosen by a generator; a proof establishes a stated property for every input satisfying its hypotheses.

| Evidence | Scope | What to examine |
|---|---|---|
| Unit tests | Selected inputs and expected outcomes | Whether the examples capture the intended behavior |
| Property tests | Bounded generated inputs | The property, generator, boundaries and discarded cases |
| Formal proofs | All modeled inputs satisfying the hypotheses | The statement, hypotheses, definitions and translation assumptions |

The runtime still needs tests even when the pure reducer has accepted proofs. Journal writes, process failures and processor behavior cross boundaries those reducer laws do not cover.

### Deterministic Unit Tests

You construct a state by hand and check a single outcome:

```elixir
test "admit request when limit permits" do
  s = {1000, 3, 0, 0, []}
  assert Ledger.step(s, {:request, 11, 300}) ==
           {{1000, 3, 300, 1, [{11, 300, :reserved}]}, :admitted, []}
end
```

**Limitation**: Unit tests only verify scenarios you explicitly thought of. They leave the rest of the state space untested.

### Property-Based Testing (`StreamData`)

Instead of one input, you define a generator and run 10,000 randomized cases:

```elixir
property "eligible request is always admitted" do
  check all {s, key, amount} <- TestGenerators.eligible_request(), max_runs: 10_000 do
    assert match?({_, :admitted, []}, Ledger.step(s, {:request, key, amount}))
  end
end
```

**Limitation**: These runs cover inputs selected by the generator, with possible repetitions. They do not establish the property universally. A generator may miss a failure involving:

* `amount_limit == 18_446_744_073_709_551_615`
* `used_amount == amount_limit - 1`
* `entries` contains a specific ordering of eight entries drawn from the seven lifecycle statuses

Targeted examples and generators biased toward boundaries help cover such combinations.

### Formal Proofs (Universal Quantification)

A formal proof establishes a statement about the modeled functions for every input satisfying its hypotheses. Proof construction and checking may perform computation; the result is a deductive argument rather than a finite sample of executions:

$$\forall s \in \text{State}, \forall k \in \mathbb{Z}, \forall a \in \mathbb{Z}^+ : \text{eligible}(s, k, a) \implies \text{result}(\text{step}(s, \text{req}(k, a))) = \text{:admitted}$$

For Hold Ledger, that claim concerns the translated semantics. The compiler and translator remain trusted. Section 6 explains how acceptance checks proof dependencies and rejects admissions or custom axioms.

---

## 2. Lean 4 for Working Programmers

Lean 4 is two things:

1. A strongly typed functional programming language with a pure core.
2. An interactive theorem prover based on dependent type theory with inductive types.

The connection between its types and propositions explains how it checks proofs.

### The Curry-Howard Correspondence (Propositions as Types)

In ordinary programming:

* `42` is a **value** of **type** `Int`.
* `"hello"` is a **value** of **type** `String`.

In a theorem prover:

* A **theorem** or **claim** is a **type**.
* A **proof** is a **value** of the proposition’s type.

| Programming Concept | Theorem Proving Concept | Meaning |
|---|---|---|
| **Type** | **Proposition / Statement** | The claim: `"For all integers x, x + 0 = x"` |
| **Expression / Value** | **Proof** | The evidence that constructs an instance of that type |
| **Kernel typechecker** | **Proof Verifier** | Checks that the proof term establishes its proposition relative to the definitions and axioms it uses |
| **Uninhabited Type** | **Falsehood** | A claim like `1 = 2` has no proof under the accepted foundations |
| `sorry` / `admit` | Assumed proof placeholder | Introduces a dependency on `sorryAx`; the term can typecheck without proving the claim. **Rejected by this repository’s acceptance checks** |

### A Complete First Proof

Create `tmp/` if needed, then save this complete standalone example as `tmp/first_proof.lean`:

```lean
import Lean

def reserve (used amount : Int) : Int := used + amount

theorem reserve_within_limit :
    ∀ (used amount limit : Int),
      amount ≤ limit - used → reserve used amount ≤ limit := by
  intro used amount limit fits
  unfold reserve
  omega
```

Run it with the repository-local toolchain:

```sh
uv run --locked python scripts/local_run.py lean tmp/first_proof.lean
```

A successful check exits with status zero. This example is ordinary Lean; it does not verify `Ledger.request/3` or its translation. It isolates the arithmetic behind admission so you can follow a whole proof before reading a translated law.

Before `intro`, the goal is the universally quantified statement after the colon. `intro` names the three integers and the implication's hypothesis. The context and remaining goal are then:

```text
used amount limit : Int
fits : amount ≤ limit - used
⊢ reserve used amount ≤ limit
```

The symbol `⊢` separates the available facts from the claim still to prove. `unfold reserve` replaces the function call with its definition:

```text
used amount limit : Int
fits : amount ≤ limit - used
⊢ used + amount ≤ limit
```

`omega` derives the inequality from `fits` and closes the goal. Lean checks the proof term produced by the tactic.

For a small exercise, change the hypothesis to `amount < limit - used` and the conclusion to `reserve used amount < limit`. The same three tactic lines prove the strict version. Removing the hypothesis leaves a false statement: `used = 0`, `amount = 1`, `limit = 0` is a counterexample.

### Tactics Used in This Guide

When writing proofs in Lean, you enter **tactic mode** using the `by` keyword. Inside `by`, each line is an instruction that transforms your proof goals:

| Tactic | Programmer's Analogy | What It Does |
|---|---|---|
| `intro x h` | Function argument binding | Introduces quantified variables and implication hypotheses as local names, as in the first proof. |
| `cases x` | Pattern matching | Splits an inductive value by constructor. For a translated `Lynx.Term`, this splits term constructors, not individual ledger statuses. |
| `rcases h with ⟨a, b⟩` | Destructuring assignment | Unpacks a conjunction ($A \land B$), existential quantifier ($\exists$), or tuple into its components. |
| `simp [lemmas]` | Macro expansion & constant folding | Repeatedly rewrites the goal using known equations until no rules apply. |
| `have name : Type := proof` | `let` binding | Proves a helpful intermediate fact locally before using it in the main goal. |
| `obtain ⟨x, hx⟩ := ...` | Destructuring a function call | Extracts a value and its proof witness from an existential lemma. |
| `omega` | Constraint solver | Solves Presburger arithmetic automatically ($+, -, \cdot \text{ by constant}, \le, <, =$ on integers). The result is a proof term checked by Lean. |
| `rfl` | Reflexive equality check | Proves $A = B$ when both sides compute to identical normal forms by definition. |
| `contradiction` | Guard failure / dead code | Closes the current branch if hypotheses contain impossible statements (like `true = false` or `x < 0` when `x >= 0`). |

---

## 3. How Lynx Connects Elixir to Lean 4

Lynx translates compiled Core Erlang into Lean definitions, so you do not manually rewrite the reducer in Lean. It obtains Core Erlang through the BEAM compilation pipeline:

```
[ lib/hold_ledger/ledger.ex ]
              |
              | 1. elixirc (mix compile)
              v
     [ BEAM Bytecode (.beam) ]
              |
              | 2. :beam_lib extracts :debug_info
              v
      [ Core Erlang AST ]
              |
              | 3. Lynx AST Translator (lynx_core_to_leanj.erl)
              v
[ Lean 4 Code + Proofs (tmp/.../laws.lean) ]
              |
              | 4. Lean 4 Kernel & Typechecker
              v
    [ Stated Laws Checked ]
```

### The AST Translation (`Lynx.Term`)

In Lean, Lynx defines an inductive type called `Lynx.Term` that models Erlang/Elixir term categories. This abbreviated declaration shows some constructors; it is not a complete definition or a proof of equivalence with the runtime:

```lean
inductive Term where
  | integer : Int → Term
  | float   : FiniteFloat → Term
  | atom    : String → Term
  | tuple   : Array Term → Term
  | map     : List (Term × Term) → Term
  | nil     : Term
  | cons    : Term → Term → Term
  | bitstring : ByteArray → Fin 8 → ... → Term
  ...
```

When Lynx reads your Elixir reducer:

```elixir
def find([], _key), do: :not_found
def find([{existing_key, _, _} = entry | rest], key) do
  if existing_key == key, do: {:ok, entry}, else: find(rest, key)
end
```

The following pseudocode shows the control flow; it is not generated or compilable Lean:

```text
find(entries, key):
  match entries:
    [] -> return :not_found
    [{existing_key, amount, status} = entry | rest] ->
      if erlang_equal(existing_key, key): return {:ok, entry}
      else: return find(rest, key)
    otherwise -> return function_clause exception
```

Generated names include `«find/2»`, and atoms become terms such as `Lynx.Term.atom "not_found"`. The current translator uses `Lynx.Result` machinery and may expose pure computations through `Except` definitions in proofs. Inspect the generated definition for the exact signature and exception representation; do not infer them from this pseudocode.

The translation models clause selection, guards, and Erlang equality. Its correctness relative to BEAM execution is a trusted assumption outside these ledger proofs. Differential tests compare sampled BEAM results with the translated definitions; compiled Lean evaluation and kernel-checked equalities provide bounded evidence, not universal correspondence.

---

## 4. Why We Have Both `Ledger` and `Spec`

A proof can establish exactly what its statement says while missing the intended requirement. For example, proving `add(a, b) = a + b` is a useful correctness claim for addition. But if a specification merely repeats an implementation's decisions, both may encode the same policy mistake.

To reduce shared implementation mistakes, `hold_ledger` uses **two strictly decoupled implementations**:

```
+---------------------------------------------------------------+
|                      TWO INDEPENDENT WORLDS                   |
|                                                               |
|  HoldLedger.Ledger (Reducer)       HoldLedger.Spec (Oracle)   |
|  * Optimized for performance       * Optimized for clarity    |
|  * Maintains running counters      * Recomputes from scratch  |
|  * Applies deltas (+amt, -amt)     * Iterates all entries     |
|  * Returns effect descriptions     * Checks effect predicates |
|  * NEVER calls Spec                * NEVER calls Ledger       |
+---------------------------------------------------------------+
```

### The Running Counter Problem

The following reducer excerpt shows only the successful admission branch:

```elixir
# State tuple: {amount_limit, hold_limit, used_amount, used_holds, entries}
def request({cap, slots, used_amount, used_holds, entries} = state, key, amount) do
  ...
  {{cap, slots, used_amount + amount, used_holds + 1, [{key, amount, :reserved} | entries]}, :admitted, []}
end
```

`Ledger` updates `used_amount` by adding `amount` to the running accumulator.

If there is a bug in delta arithmetic (e.g. timeout subtracts amount when it shouldn't), `used_amount` drifts from the entry totals.

The following accounting-only sketch illustrates recomputation in `HoldLedger.Spec`; it is not the complete `valid?/1` implementation:

```elixir
def hold_amount([]), do: 0
def hold_amount([{_, amount, status} | rest]) do
  if holding?(status), do: amount + hold_amount(rest), else: hold_amount(rest)
end

def valid?({amount_limit, hold_limit, used_amount, used_holds, entries}) do
  used_amount == hold_amount(entries) and
  used_holds == hold_count(entries) and
  used_amount <= amount_limit and
  used_holds <= hold_limit
end
```

The full invariant also checks integer fields, nonnegative limits and counters, a proper entry list, positive integer amounts, known statuses, and unique integer keys. It validates entry shape before summing. See `lib/hold_ledger/spec.ex` and the [Specification](specification.md).

`Spec` does not trust running counters. It walks the entry list and sums amounts from scratch. Independence helps catch delta-accounting errors, but both implementations could still share an incorrect understanding of the contract.

PO-S states that every arbitrary event term preserves `Spec.valid?/1` when the initial state is valid. This is one specific preservation claim; it does not establish every part of the specification. Consult the [Verification](verification.md) guide for proof coverage, acceptance commands, and provenance.

### Accounting and Remote Exposure

Correct local totals alone do not bound remote authorizations. If a void request released local capacity before the processor confirmed it, another hold could be admitted while the old authorization remained live. The ledger therefore retains capacity in `:voiding`. A trusted confirmation releases that capacity and retires the corresponding durable obligation in the composite reducer; the independent Spec checks their coupling.

Remote exposure bounds also depend on truthful processor outcomes, stable identities and amounts, deduplication, and a terminal fence against delayed authorization after void confirmation. The [Verification guide](verification.md#added-model-boundaries) describes those conditional theorems. A processor capability declaration cannot establish that a real processor meets the assumptions.

---

## 5. Reading a Duplicate-Request Proof

Law **PO-A4 Duplicate** (`test/laws/po_a4_duplicate_test.exs`) states that, on a valid ledger with an integer key already present at the same positive integer amount, resubmission returns `:duplicate` and leaves the ledger unchanged across all valid statuses.

### The Elixir Law Declaration

The law file states the executable contract and cites a shared theorem. This excerpt omits the surrounding module:

```elixir
laws "po_a4_duplicate" do
  law po_a4_duplicate(s, key, amount, status),
    requires:
      Spec.valid?(s) and is_integer(key) and is_integer(amount) and amount > 0 and
        Spec.lookup(elem(s, 4), key) == {:ok, {key, amount, status}},
    expects:
      Ledger.request(s, key, amount) == {s, :duplicate, []},
    proof: ~LEAN"""
    exact Elixir.HoldLedger.ProofContracts.«po_a4_duplicate/4» s key amount status requires
    """
end
```

* `requires:` ($P$):
  1. $s$ is valid according to `Spec.valid?/1`.
  2. `key` is an integer.
  3. `amount` is a positive integer.
  4. Looking up `key` in entries returns `{:ok, {key, amount, status}}`.

* `expects:` ($Q$):
  Calling `Ledger.request(s, key, amount)` returns `{s, :duplicate, []}`.

### Check That the Hypotheses Can Hold

A law of the form `P → Q` says nothing about inputs for which `P` is false. This complete Lean example has contradictory requirements and an arbitrary conclusion:

```lean
import Lean

theorem impossible_admission :
    ∀ (amount : Int), amount > 0 ∧ amount ≤ 0 → amount = 42 := by
  intro amount requirements
  rcases requirements with ⟨positive, nonpositive⟩
  omega
```

There is no integer satisfying both requirements, so the theorem holds vacuously. A valid proof does not establish that its precondition describes any useful case.

For PO-A4, a concrete witness is `s = {1000, 3, 300, 1, [{11, 300, :reserved}]}`, `key = 11`, `amount = 300`, `status = :reserved`. It satisfies the requirements, and resubmission returns `{s, :duplicate, []}`. The repository keeps concrete precondition witnesses alongside its laws. A witness rules out an entirely impossible precondition. Reviewers must still judge whether the law includes every intended case, including terminal statuses here. Never add restrictions merely to obtain a proof.

### Reading the Shared Lean Proof

The reusable theorem lives in `test/support/lean/Lookup.lean`. It cites lookup compatibility from `CoreLookup.lean`, then decomposes the valid state and discharges the duplicate-request branch. The following excerpts explain that argument; omitted steps are needed for a complete proof. Read `Except.ok v` as a successful computation returning `v`, `∃` as “there exists,” and `∧` as “and.” The notation `«find/2»` quotes an Elixir function name that contains punctuation; `#[...]` constructs a Lean array.

```lean
have compatible : ∀ es k, Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    ∃ v, Elixir.HoldLedger.Ledger.«find/2» es k = Except.ok v ∧
      Elixir.HoldLedger.Spec.«lookup/2» es k = Except.ok v ∧
      (v = Lynx.Term.atom "not_found" ∨ ∃ (ek : Lynx.Term) (n : Int) (st : Lynx.Term),
        v = Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[ek, Lynx.Term.integer n, st]]) := by
  intro es k h
  fun_induction Elixir.HoldLedger.Ledger.«find/2» es k
  ...
```

#### Step 1: Proving Compatibility between `Ledger.find` and `Spec.lookup`

In Elixir, `Ledger` uses `find/2`, while `Spec` uses `lookup/2`. They are written separately.
The shared lookup lemma establishes that on any well-formed entry list, `find` and `lookup` return identical values. The duplicate and conflict proofs reuse it with `have compatible := HoldLedgerProof.compatible_2`; they do not repeat its list induction.

#### Step 2: Unpacking the State

```lean
have shaped : ∀ s, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
    ∃ al hl ua uh es, s = Lynx.Term.tuple #[al, hl, ua, uh, es] ∧
      Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true := by
  ...
```

This lemma proves that any state that satisfies `Spec.valid?` must be a 5-tuple whose fifth element is a proper entry list.

#### Step 3: Pushing Hypotheses and Simplifying

```lean
simp only [«po_a4_duplicate:requires/4», bind, Except.bind] at requires
all_goals repeat' (split at requires <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
```

This tells Lean:

1. Unfold the generated definition of `requires`.
2. Split the translated conditional branches used to evaluate the Elixir `and` expressions.
3. Eliminate impossible branches.

#### Step 4: Discharging the Goal

```lean
all_goals obtain ⟨al, hl, ua, uh, es, rfl, hp⟩ := shaped s (by assumption)
all_goals obtain ⟨v, hf, hl, hs⟩ := compatible es key hp
all_goals rcases hs with rfl | ⟨ek, n, st, rfl⟩
all_goals simp_all [«po_a4_duplicate:ensures/4», Elixir.HoldLedger.Ledger.«request/3», ...]
```

Because `compatible` proved that `find` will find the exact `{key, amount, status}` tuple we assumed in `requires`, `Ledger.request/3` takes its first branch:

```elixir
case find(entries, key) do
  {:ok, {_, ^amount, _}} -> {state, :duplicate, []}
```

Lean's simplifier evaluates the pattern match, finds that the returned tuple equals `{s, :duplicate, []}`, and closes the theorem.

---

## 6. What Proof Acceptance Checks

The kernel checks a proof against its statement and dependencies. Acceptance also needs to reject admissions and unexpected axioms. These checks cannot detect a requirement omitted from the statement or an overly restrictive hypothesis; that still takes specification review.

### Source Scan

`scripts/run_laws.py` scans every law file and shared `.lean` source before execution. If it encounters:

* `sorry` (Lean's "skip this proof" keyword)
* `admit`
* `axiom`
* `unsafe`
* `native_decide`

The runner terminates with an immediate error:

```text
RuntimeError: Forbidden proof escape in test/laws/...
```

### Axiom Audit

When Lean completes a proof, its environment tracks every axiom used in the deduction tree.
This repository’s axiom audit permits only three foundational axioms:

1. `propext` (Propositional Extensionality: equivalent propositions are equal).
2. `Quot.sound` (Quotient Soundness: equivalence classes behave soundly).
3. `Classical.choice` (The Axiom of Choice).

Full-stage acceptance audits the exported proof dependencies and rejects axioms outside this allowlist, including `sorryAx`. A direct `mix test` proof attempt does not run the repository’s full exported-checker and axiom-audit pipeline.

### Six Checker Configurations

Checking the theorems with Lean is not the final step. Lynx exports the elaborated proof objects to `.ndjson` files. We then run **six checker configurations** against those proof objects:

* **Lean default**
* **Lean paranoid** (a stricter configuration of the Lean checker)
* **lean4lean** (an independent reimplementation of the Lean kernel in Lean)
* **nanoda** (independent checker written in Rust)
* **con-leche** (independent external checker)
* **con-ron** (independent external checker)

Lean default and paranoid are configurations of Lean, not two independently implemented kernels. The other checkers provide implementation diversity. For full-stage acceptance, all six configurations must agree that the proof terms are valid. A full-suite run checks one combined export containing all selected law proofs and dependencies. See [Verification](verification.md) for current commands, source/export identities and report provenance.

### Mutation Testing

The ten patches under `mutants/` deliberately break contract behavior: terminal-key reuse, timeout accounting, retry identity, exact-fit and positive admission, transport acknowledgments, void effects, decline accounting, restart conversion and pending-void retention.

The optional mutation experiment checks concrete assertions, ordinary tests and targeted formal attempts in isolated copies. It tests whether those checks detect the planted violations. A failed tactic or timeout alone does not establish a counterexample. See [Testing](testing.md#deliberate-mutations) for commands and costs.

---

## 7. Developing a Lynx Law

Start by running the complete Lean example in section 2 and making the strict-inequality change. The following exercise moves to Lynx and deliberately begins with an unsuccessful proof attempt. It is a debugging route rather than a complete solution.

### Step 1: Write the Spec Predicates and Law

For a standalone development attempt, add a law to `test/laws/my_law_test.exs`. This example uses upstream `Lynx.Case` directly and does not yet participate in the repository’s shared-theory runner:

```elixir
defmodule HoldLedger.Laws.MyLawTest do
  use ExUnit.Case
  use Lynx.Case
  alias HoldLedger.{Ledger, Spec}

  laws "my_law" do
    law my_property(s, key),
      requires: Spec.valid?(s) and is_integer(key),
      expects: Spec.valid?(elem(Ledger.step(s, {:timeout, key}), 0)),
      proof: ~LEAN"""
      rfl
      """
  end
end
```

### Step 2: Run with Debug Output

After the setup in [Getting started](getting-started.md), run the specific law file with debug output and caching disabled:

```sh
LYNX_CACHE=0 LYNX_DEBUG=lean uv run --locked python scripts/local_run.py mix test test/laws/my_law_test.exs --only laws
```

The `rfl` placeholder is an intentional first proof attempt, not a completed proof. For this preservation statement it will generally leave goals unsolved. Read the actual diagnostics for the generated goal, hypotheses, and translated-source directory; wording and paths depend on the Lynx version and group name. A failed tactic or timeout is not a concrete counterexample.

### Step 3: Inspect the Generated Lean Code

Open the directory reported by Lynx and locate the generated `.lean` files for `Ledger`, `Spec`, and the law module. Inspect the actual function signatures and generated `requires` and `ensures` definitions. The translation may introduce helper definitions and exception plumbing, so the generated code need not resemble a short hand-written Lean function.

### Step 4: Author the Proof

Iteratively replace `rfl` with tactic steps:

1. Inspect the existing proof context. Lynx supplies a `requires` hypothesis; use `intro` only when the current goal calls for it.
2. Unfold relevant definitions, for example `simp only [«my_property:requires/2», bind, Except.bind] at requires`.
3. Use constructor case analysis and the invariant’s status restrictions to eliminate impossible branches. Apply induction when reasoning about recursive lists.
4. Use `omega` for supported integer constraints and `simp_all` with the necessary definitions and lemmas for equalities.

Keep `Ledger` and `Spec` independent. Do not narrow a law’s input domain or weaken its conclusion to obtain a pass, and do not change both implementations merely to satisfy a test. The duplicate-law walkthrough shows this process; its omitted steps matter, so consult the shared theorem source before copying a proof.

### Step 5: Integrate a Repository Law

Keep concrete precondition witnesses and appropriate executable tests alongside the contract. Maintained laws use `HoldLedger.ProofCase` and shared theory under `test/support/lean/`; the catalog and obligation inventory record what must be checked. The [Verification guide](verification.md#shared-proof-theory) explains the adapter, dependency ordering and development cache. Follow an existing law when integrating a new one, and register its obligations before claiming suite coverage.

For an already registered law, the acceptance command is:

```sh
uv run --locked python scripts/run_laws.py --slug po_a4_duplicate --stage full --report tmp/verification/duplicate.json
```

Development proof attempts and full acceptance are different checks. See [Verification](verification.md) for the exact runner contract and costs.

---

## 8. Frequently Asked Questions

### Why not write the whole ledger in Lean and extract Elixir code?

This project keeps the ledger and its journaled OTP runtime in Elixir. Lynx lets it state and prove laws about translated pure functions without maintaining a separate hand-written Lean implementation of the reducer. The runtime continues to use GenServer, supervision, and the owned framed journal, with behavior tested separately.

### What do the terminal and history laws add?

The catalog lists the maintained formal obligations. The two PO-B5 groups establish that declined and voided entries retain their key, amount and terminal status after any next event on a valid ledger. Their original argument domains include loose numeric equality; the proofs do not add integer guards to the queried key or amount.

PO-C3 reasons over a proper finite list of arbitrary event terms. It proves that reducer replay agrees with `Spec.expected_run/2`, preserves existing identities and terminal entries, and has independent approval evidence for authorization. The History proof uses one-step oracle agreement, successor validity, identity composition, terminal lookup preservation and authorization evidence.

Deterministic tests and bounded generated properties complement these proofs. The ledger and composite properties use 10,000 cases; the attempt interleaving property uses 1,000. The executed test summary and coverage output report the current sample counts; those counts are distinct from formal quantification. A failed tactic or timeout alone is never a concrete counterexample.

### Does formal verification guarantee my system will never fail?

No. Accepted proofs establish specific law statements about the translated pure functions, under their explicit preconditions and trusted assumptions. The supported selection includes every cataloged obligation, but the catalog is a specified set of claims rather than a blanket proof of every possible requirement or of the OTP runtime.

Storage durability and processor deduplication remain external assumptions. Runtime fault tests exercise the journal and server under specific failures; they do not establish physical durability or processor compliance.

Tests, specified laws, proof maintenance, and operational checks remain complementary. Review the specification itself and the compiler/translator assumptions as well as hardware, network, and durability boundaries.

---

## 9. Next Steps

* Read [**Architecture Guide**](architecture.md) for how the pure core connects to GenServer and the owned framed journal.
* Read [**Specification Guide**](specification.md) for every event, status, and transition rule.
* Read [**Verification Guide**](verification.md) for checker commands, axiom configurations, and benchmark costs.
* Run the interactive demo:
  ```sh
  mix run scripts/demo.exs
  ```
