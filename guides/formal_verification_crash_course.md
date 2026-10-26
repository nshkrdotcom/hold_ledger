# Formal Verification Crash Course: From Tests to Proofs

This guide is written for software engineers who build backend and distributed systems in Elixir, understand testing and property-based testing, but have never touched an interactive theorem prover like Lean.

It introduces formal verification in `hold_ledger`: how proofs complement unit and property tests, how propositions can be represented as types, how Lean 4 and Lynx work with compiled Core Erlang, and how to read and develop a machine-checked proof. Code blocks marked as excerpts or pseudocode omit details; the executable law files and their shared Lean theory remain the authoritative examples.

---

## 1. The Spectrum of Confidence

Every software team asks the same question: *"How do we know this works?"*

In financial systems and stateful engines, our tools sit on an escalating spectrum:

```
[ Unit Tests ] ---------> [ Property Tests ] ---------> [ Formal Proofs ]
Checks 1 path             Checks 10,000 paths          Proves stated properties
(Manual examples)         (Randomized generator)       (Universal quantification)
```

### Level 1: Deterministic Unit Tests
You construct a state by hand and check a single outcome:
```elixir
test "admit request when limit permits" do
  s = {1000, 3, 0, 0, []}
  assert Ledger.step(s, {:request, 11, 300}) ==
           {{1000, 3, 300, 1, [{11, 300, :reserved}]}, :admitted, []}
end
```
**Limitation**: Unit tests only verify scenarios you explicitly thought of. They leave the rest of the state space untested.

### Level 2: Property-Based Testing (`StreamData`)
Instead of one input, you define a generator and run 10,000 randomized cases:
```elixir
property "eligible request is always admitted" do
  check all {s, key, amount} <- TestGenerators.eligible_request(), max_runs: 10_000 do
    assert match?({_, :admitted, []}, Ledger.step(s, {:request, key, amount}))
  end
end
```
**Limitation**: 10,000 test runs is a statistical sample, not a proof. If a failure only occurs when:
* `amount_limit == 18_446_744_073_709_551_615`
* `used_amount == amount_limit - 1`
* `entries` contains a specific ordering of eight entries drawn from the seven lifecycle statuses

Random generation may miss that exact combination. In cryptography and financial ledgers, the bug lives in the needle, not the haystack.

### Level 3: Formal Proofs (Universal Quantification)
A formal proof establishes a statement about the modeled functions for every input satisfying its hypotheses. Proof construction and checking may perform computation; the result is a deductive argument rather than a finite sample of executions:

$$\forall s \in \text{State}, \forall k \in \mathbb{Z}, \forall a \in \mathbb{Z}^+ : \text{eligible}(s, k, a) \implies \text{result}(\text{step}(s, \text{req}(k, a))) = \text{:admitted}$$

A checked proof establishes the statement for every input satisfying its hypotheses, within the translated semantics and trusted compiler/translator boundary. This project permits only the foundational axioms `propext`, `Quot.sound`, and `Classical.choice`; admissions and custom axioms are forbidden.

---

## 2. Lean 4 for Working Programmers

Lean 4 is two things:
1. A pure, strongly typed functional programming language (like Haskell or OCaml).
2. An interactive theorem prover based on dependent type theory with inductive types.

You do not need a degree in formal logic to use it. You only need to understand one foundational idea.

### The Curry-Howard Correspondence (Propositions as Types)

In ordinary programming:
* `42` is a **value** of **type** `Int`.
* `"hello"` is a **value** of **type** `String`.

In a theorem prover:
* A **theorem** or **claim** is a **type**.
* A **proof** is a **value** (or program) that produces that type.

| Programming Concept | Theorem Proving Concept | Meaning |
|---|---|---|
| **Type** | **Proposition / Statement** | The claim: `"For all integers x, x + 0 = x"` |
| **Expression / Value** | **Proof** | The evidence that constructs an instance of that type |
| **Kernel typechecker** | **Proof Verifier** | Checks that the proof term establishes its proposition relative to the definitions and axioms it uses |
| **Uninhabited Type** | **Falsehood** | A claim like `1 = 2` has no values. You cannot construct one without cheating |
| `sorry` / `admit` | Assumed proof placeholder | Introduces a dependency on `sorryAx`; the term can typecheck without proving the claim. **Rejected by this repository’s acceptance checks** |

When you see:
```lean
theorem add_zero (x : Int) : x + 0 = x := by
  omega
```
The theorem takes an integer `x` and provides a proof of the proposition `x + 0 = x`. The tactic `omega` constructs a proof term that the kernel checks. In a standalone file, import `Lean` to make the tactic available.

### The Essential Tactic Cheat Sheet

When writing proofs in Lean, you enter **tactic mode** using the `by` keyword. Inside `by`, each line is an instruction that transforms your proof goals:

| Tactic | Programmer's Analogy | What It Does |
|---|---|---|
| `intro x h` | Function argument binding | Pops universal quantifiers ($\forall$) or implications ($\implies$) off the goal and binds them to local variable `x` with hypothesis `h`. |
| `cases x` | Pattern matching | Splits an inductive value by constructor. Here, a status is represented as `Lynx.Term`, so `cases status` splits term constructors, including `atom`, rather than the seven ledger statuses; permitted atom strings require further reasoning. |
| `rcases h with ⟨a, b⟩` | Destructuring assignment | Unpacks a conjunction ($A \land B$), existential quantifier ($\exists$), or tuple into its components. |
| `simp [lemmas]` | Macro expansion & constant folding | Repeatedly rewrites the goal using known equations until no rules apply. |
| `have name : Type := proof` | `let` binding | Proves a helpful intermediate fact locally before using it in the main goal. |
| `obtain ⟨x, hx⟩ := ...` | Destructuring a function call | Extracts a value and its proof witness from an existential lemma. |
| `omega` | Constraint solver | Solves Presburger arithmetic automatically ($+, -, \cdot \text{ by constant}, \le, <, =$ on integers). You never have to prove $x + 1 > x$ manually. |
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

The translation models clause selection, guards, and Erlang equality. Its correctness relative to BEAM execution is a trusted assumption outside these ledger proofs.

---

## 4. Why We Have Both `Ledger` and `Spec`

A common trap in formal verification is proving a tautology:

> *"I wrote `add(a, b) => a + b`. Then I proved `add(a, b) == a + b`. It passed!"*

This proves your code equals itself, not that it is correct.

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

---

## 5. Walkthrough: Deconstructing a Real Proof

Let's dissect law **PO-A4 Duplicate** (`test/laws/po_a4_duplicate_test.exs`), which states that, on a valid ledger with an integer key already present at the same positive integer amount, resubmission returns `:duplicate` and leaves the ledger unchanged across all valid statuses.

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

### The Lean Proof (Step-by-Step)

The reusable theorem lives in `test/support/lean/Lookup.lean`. It cites lookup compatibility from `CoreLookup.lean`, then decomposes the valid state and discharges the duplicate-request branch. The following excerpts explain that argument; omitted steps are needed for a complete proof:

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
2. Split on all `and` conjunctions.
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
Lean's simplifier evaluates the pattern match, finds that the returned tuple equals `{s, :duplicate, []}`, and closes the theorem. Q.E.D.

---

## 6. How We Know the Proofs Aren't Cheating

When reading formal claims, healthy skepticism is mandatory. How do you know the author didn't add an axiom that asserts `True = False`?

We defend against proof tampering with four guardrails:

### 1. Static Anti-Cheat Checker
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

### 2. Axiom Audit
When Lean completes a proof, its environment tracks every axiom used in the deduction tree.
This repository’s axiom audit permits only three foundational axioms:
1. `propext` (Propositional Extensionality: equivalent propositions are equal).
2. `Quot.sound` (Quotient Soundness: equivalence classes behave soundly).
3. `Classical.choice` (The Axiom of Choice).

Full-stage acceptance audits the exported proof dependencies and rejects axioms outside this allowlist, including `sorryAx`. A direct `mix test` proof attempt does not run the repository’s full exported-checker and axiom-audit pipeline.

### 3. Six Checker Configurations
Checking the theorems with Lean is not the final step. Lynx exports the elaborated proof objects to `.ndjson` files. We then run **six checker configurations** against those proof objects:
* **Lean default**
* **Lean paranoid** (a stricter configuration of the Lean checker)
* **lean4lean** (an independent reimplementation of the Lean kernel in Lean)
* **nanoda** (independent checker written in Rust)
* **con-leche** (independent external checker)
* **con-ron** (independent external checker)

Lean default and paranoid are configurations of Lean, not two independently implemented kernels. The other checkers provide implementation diversity. For full-stage acceptance, all six configurations must agree that the proof terms are valid. A full-suite run checks one combined export containing all selected law proofs and dependencies. See [Verification](verification.md) for current commands, source/export identities and report provenance.

### 4. Mutation Testing (Mutant Catching)
Under `mutants/`, we maintain ten deliberate source patches that inject realistic bugs into `lib/hold_ledger/ledger.ex`:
* `M1`: Mistakes terminal keys (`:voided`, `:declined`) for fresh keys.
* `M2`: Subtracts capacity on timeout.
* `M3`: Generates an authorize effect with `key + 1` instead of `key` on retry.
* `M4`: Changes `amount > limit - used` to `>=` (rejects exact fit).
* `M5`: Rejects every positive request unconditionally.
* `M6`: Treats transport ACKs as authorization approvals.
* `M7`: Omits the required remote void intent.
* `M8`: Corrupts decline accounting.
* `M9`: Leaves sent entries unchanged on restart.
* `M10`: Releases an authorized hold before terminal void confirmation.

When you run:
```sh
uv run --locked python scripts/run_mutants.py --execute
```
The test runner applies each patch in an isolated temporary directory, runs both the ExUnit tests and the formal proofs, and records the concrete assertions, ordinary-test results, and targeted formal attempts. A failed proof alone does not establish a counterexample.

---

## 7. The Practical Workflow: How to Write and Debug a Law

When developing a new law or modifying existing behavior, use this feedback loop:

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
A direct upstream `Lynx.Case` attempt runs a development law without registering it in the catalog. To make a law part of this repository’s maintained suite:

- Keep its concrete witnesses, assertions and appropriate property coverage alongside its executable contract.
- Use `HoldLedger.ProofCase` for the maintained law wrapper. Put reusable theorem declarations in `test/support/lean/`, and map the law name to its theory module in `library.json`. Use the existing laws as examples.
- Register its group, file, law name, arity, witness path, purpose and status in `verification/laws.json`. Update the independently reviewed `verification/obligations.json` inventory, tooling tests and coverage documentation when extending the catalog. Native groups register fully qualified theorem names; the runner checks them with Lean and rejects orphan theory modules. The supported selection currently includes all cataloged groups; it does not silently omit unfinished obligations.
- Validate the catalog, then run the selected law through the full cold proof/export/checker stage. Keep historical provenance separate from new results.

The adapter derives shared contract predicates from the actual law declarations and loads the shared theory after translated Ledger/Spec definitions. The final law theorem must still typecheck against its own original predicates. A `prelude` is suitable for generic tactics or term lemmas; it loads too early to import concrete Ledger lemmas directly.

For iterative development of an existing shared proof, `HOLD_LEDGER_PROOF_CACHE=1` can reuse already checked, source-keyed dependencies in a direct test attempt. Changes invalidate dependent keys. The acceptance runner disables this development cache and rejects cached module results.

For an already registered law, the acceptance command is:

```sh
uv run --locked python scripts/run_laws.py --slug po_a4_duplicate --stage full --report tmp/verification/duplicate.json
```

Development proof attempts and full acceptance are different checks. See [Verification](verification.md) for the exact runner contract and costs.

---

## 8. Frequently Asked Questions

### Why not write the whole ledger in Lean and extract Elixir code?
This project keeps the ledger and its journaled OTP runtime in Elixir. Lynx lets it state and prove laws about translated pure functions without maintaining a separate hand-written Lean implementation of the reducer. The runtime continues to use GenServer, supervision, and the owned framed journal, with behavior tested separately.

Extraction and foreign-function integration are other design choices; this project does not establish that they are impossible or inherently unsuitable.

### What do the terminal and history laws add?

The catalog lists the maintained formal obligations. The two PO-B5 groups establish that declined and voided entries retain their key, amount and terminal status after any next event on a valid ledger. Their original argument domains include loose numeric equality; the proofs do not add integer guards to the queried key or amount.

PO-C3 reasons over a proper finite list of arbitrary event terms. It proves that reducer replay agrees with `Spec.expected_run/2`, preserves existing identities and terminal entries, and has independent approval evidence for authorization. The History proof uses one-step oracle agreement, successor validity, identity composition, terminal lookup preservation and authorization evidence.

Deterministic tests and 10,000 generated examples per property complement these proofs. The executed test summary and coverage output report the current sample counts; those counts are distinct from formal quantification. A failed tactic or timeout alone is never a concrete counterexample.

### Does formal verification guarantee my system will never fail?
No. Accepted proofs establish specific law statements about the translated pure functions, under their explicit preconditions and trusted assumptions. The supported selection includes every cataloged obligation, but the catalog is a specified set of claims rather than a blanket proof of every possible requirement or of the OTP runtime.

It does not prove that:
* Your hard drive won't suffer physical sector corruption.
* The Linux kernel won't lie about `fsync`.
* A remote payment processor honors deduplication keys.
* A datacenter won't lose power.

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

## Pending voids and external exposure

A pure accounting invariant alone does not bound remote authorizations when local
capacity is released before remote void confirmation. The ledger retains capacity
in `:voiding`; one internal confirmation event releases it and retires its outbox
obligation in a composite fold. The independent Spec checks both the transition
and the invariant that voiding keys equal unique obligation keys.

Remote exposure requires an environment model: no spontaneous authorization,
truthful decisions, stable identity/amount and a terminal fence preventing delayed
authorizations after void confirmation. A capability declaration cannot prove
those assumptions. Differential testing samples actual translated code against
BEAM; compiled Lean evaluation and kernel-checked equalities provide separate
bounded evidence. Consult the verification guide for the exact accepted scope.
