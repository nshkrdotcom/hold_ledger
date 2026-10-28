defmodule HoldLedgerReviewWeb.EducationComponents do
  @moduledoc "Static teaching copy using the workbench's existing review state."
  use HoldLedgerReviewWeb, :html
  alias HoldLedgerReviewWeb.{Glossary, ReviewProgress}

  attr :reviews, :list, required: true

  def primer(assigns) do
    ~H"""
    <a class="skip-scenarios" href="#new-review-choices">Skip to the scenarios ↓</a>
    <details id="review-primer" class="primer" open={@reviews == []}>
      <summary>
        {if @reviews == [], do: "Read this first", else: "Read the primer again"}
        <small>Allow about 10 minutes</small>
      </summary>
      <div class="primer-body">
        <section
          id="primer-people"
          data-source="guides/agentic_verification.md#run-an-agent-through-a-bounded-change;guides/human_review.md#what-to-delegate-and-what-to-decide"
        >
          <h2>1. Why is a person needed?</h2>
          <p>
            Suppose you ask a coding agent to build a payment system. It writes code, writes rules for that code, and supplies proofs that the code obeys those rules. Who checks whether it chose the rules you meant?
          </p>
          <p>
            That is your job here.
            <.term key="formal_verification">Formal verification</.term>
            means using a mathematical proof to establish a precisely stated property of a program. A property might say that every request which fits the available limits must be admitted.
          </p>
          <table>
            <thead>
              <tr>
                <th>Who</th><th>What they do</th><th>What you look at</th>
              </tr>
            </thead><tbody>
              <tr>
                <td>A coding agent</td><td>Can write the code, precise rules and proofs.</td><td>
                  The behavior and rules it chose.
                </td>
              </tr>
              <tr>
                <td><.term key="lean">Lean</.term>, a proof checker</td><td>
                  Checks that a supplied proof establishes its exact statement.
                </td><td>The statement, its assumptions and the recorded checker result.</td>
              </tr>
              <tr>
                <td>You</td><td>Decide whether the rules express the policy you want.</td><td>
                  Examples of what those rules allow and reject.
                </td>
              </tr>
            </tbody>
          </table>
          <p>
            A proof answers the question written in its statement. Ask whether the total stays below 100 cents, and an implementation that refuses every request can satisfy that question. You also need to ask whether a request that fits gets accepted.
          </p>
          <p>
            You do not need to read Lean to use this page. This app never runs Lean; it calculates examples and displays a separate proof report if one is attached. The three roles above describe an agent-assisted workflow, regardless of who authored a particular file.
          </p>
        </section>
        <section
          id="primer-ledger"
          data-source="README.md#the-ledger-in-a-few-steps;guides/specification.md#uncertain-outcomes-and-identities"
        >
          <h2>2. What is a payment hold?</h2>
          <p>
            Imagine a hotel reserving money on your card before it knows the final bill. The payment service could approve the reservation while its reply gets lost on the way back. From the hotel's side, silence leaves the outcome unknown.
          </p>
          <p>
            A
            <.term key="hold">hold</.term>
            is a reservation of money. Hold Ledger keeps a record of holds for one account, with two limits: total cents reserved and number of holds. Each hold gets an integer <.term key="identity">key</.term>; the record remembers it after release, and retries use that same key and amount.
          </p>
          <ol>
            <li>Start with a 100-cent limit, room for two holds, and no money reserved.</li>
            <li>
              Request a 100-cent hold under key 11. The ledger admits it and reserves all 100 cents.
            </li>
            <li>
              Dispatch its authorization. The ledger records that a request to the payment service is needed.
            </li>
            <li>
              Let that request time out. The ledger marks its outcome unknown and keeps the 100 cents reserved.
            </li>
            <li>
              Ask for another 100 cents under key 12. The ledger refuses: the first hold might still exist remotely.
            </li>
          </ol>
          <p>
            The code being examined is <.term key="pure">pure</.term>: it calculates a next state and requests for outside work without doing that work. Calculating this example moves no money. An issued hold stays counted until trusted evidence permits release; a reservation that was never dispatched can be cancelled locally.
          </p>
        </section>
        <section
          id="primer-lifecycle"
          data-source="README.md#the-ledger-in-a-few-steps;guides/specification.md#events;guides/specification.md#state-and-validity"
        >
          <h2>3. What happens during a hold's life?</h2>
          <pre aria-label="Hold lifecycle">request → reserved → sent ── timeout or restart → unknown
                      ↑                              │
                      └──── retry, same key ──────────┘

    sent or unknown ── approval → authorized ── void → voiding
                                                    │
                                    trusted confirmation
                                                    ↓
                                                  voided

    sent or unknown ── decline → declined
    reserved ── local cancellation → voided</pre>
          <p>
            Read the arrows as changes in the ledger's record. Sending a request does not establish approval, and asking to cancel an approved hold does not establish cancellation. A timeout keeps the reservation because the service may have acted before the reply was lost.
          </p>
          <table>
            <thead>
              <tr>
                <th>Status</th><th>What it means</th><th>Counts against both limits?</th>
              </tr>
            </thead><tbody>
              <tr :for={status <- ~w(reserved sent unknown authorized voiding declined voided)}>
                <td>
                  <.term key={status}>{status}</.term>
                </td><td>{Glossary.one_line(status)}</td><td>
                  {if status in ~w(declined voided), do: "No", else: "Yes"}
                </td>
              </tr>
            </tbody>
          </table>
          <p>
            An
            <.term key="event">event</.term>
            is an input telling the ledger what happened or what to calculate next. The full ledger accepts these events; the example editor supports request, dispatch, timeout and void.
          </p>
          <ul class="event-vocabulary">
            <li><.term key="request">Request</.term>: reserve an amount.</li><li>
              <.term key="dispatch">Dispatch</.term>: request authorization.
            </li>
            <li>
              <.term key="timeout">Timeout</.term>
              or <.term key="restart">restart</.term>: mark sent outcomes unknown.
            </li><li><.term key="retry">Retry</.term>: reuse the unknown hold's identity.</li>
            <li>
              <.term key="processor_result">Processor result</.term>: record approval or decline.
            </li><li>
              <.term key="transport_ack">Transport acknowledgment</.term>: delivery information, never approval.
            </li>
            <li><.term key="void">Void</.term>: cancel locally or request remote cancellation.</li><li>
              <.term key="void_confirmed">Void confirmed</.term>: record trusted confirmation.
            </li>
          </ul>
          <p>
            <.term key="effects">Effects</.term>
            are requests for outside work, such as authorizing or cancelling a hold. They describe what the runtime should attempt. They do not prove that a service received or completed anything.
          </p>
        </section>
        <section
          id="primer-law"
          data-source="test/laws/po_a2_test.exs#po_a2;lib/hold_ledger/spec.ex#request_eligible?;verification/laws.json"
        >
          <h2>4. What does a rule look like?</h2>
          <p>
            A
            <.term key="law">law</.term>
            is a precise rule about the code. It has a
            <.term key="precondition">requires</.term>
            part saying when it applies and an
            <.term key="postcondition">expects</.term>
            part saying what must follow. Here is the positive-admission rule, called <code>po_a2</code>.
          </p>
          <table>
            <thead>
              <tr>
                <th>Part of the rule</th><th>Read it this way</th>
              </tr>
            </thead><tbody>
              <tr>
                <td>When</td><td>
                  The starting state is valid; the key is fresh; the amount is positive; both limits have room, including an exact fit.
                </td>
              </tr>
              <tr>
                <td>The ledger must</td><td>
                  Add a reserved entry with that key and amount; increase the amount total by exactly that amount and the count by one.
                </td>
              </tr>
              <tr>
                <td>It must also</td><td>
                  Return “admitted,” request no outside work, and agree with <.term key="spec">Spec</.term>, the independently written reference model.
                </td>
              </tr>
            </tbody>
          </table>
          <p>
            For an empty 100-cent account, a fresh request for exactly 100 cents qualifies. Returning “insufficient amount” would break this rule. The reference is useful for comparison, but it cannot decide which payment policy you intended.
          </p>
          <details>
            <summary>Read the original Elixir declaration</summary><pre phx-no-curly-interpolation>law(po_a2(s, key, amount),
    requires: Spec.request_eligible?(s, key, amount),
    expects:
    Ledger.request(s, key, amount) ==
      {{elem(s, 0), elem(s, 1), elem(s, 2) + amount, elem(s, 3) + 1,
        [{key, amount, :reserved} | elem(s, 4)]}, :admitted, []} and
      Ledger.request(s, key, amount) == Spec.expected_step(s, {:request, key, amount}),
    proof: ~LEAN&quot;&quot;&quot;
    exact Elixir.HoldLedger.ProofContracts.«po_a2/3» s key amount requires
    &quot;&quot;&quot;
    )</pre>
          </details>
          <p>
            There are 49 registered rule groups, about fifty in all. Some describe a single operation; others describe histories or supporting models. These four show the range:
          </p>
          <ul>
            <li :for={slug <- ~w(po_exposure_retain po_b5_declined po_b6 po_b3)}>
              {Glossary.law_description(slug)} <small>{slug}</small>
            </li>
          </ul>
        </section>
        <section
          id="primer-proof"
          data-source="README.md#what-the-checks-establish;guides/formal_verification_crash_course.md#how-lynx-proves-something-about-elixir;guides/agentic_verification.md#compare-candidate-contracts"
        >
          <h2>5. What can a proof tell you?</h2>
          <table>
            <thead>
              <tr>
                <th>A checked proof establishes</th><th>You still need to ask</th>
              </tr>
            </thead><tbody>
              <tr>
                <td>The stated result for every input meeting the stated assumptions.</td><td>
                  Are important cases missing from those assumptions?
                </td>
              </tr>
              <tr>
                <td>The property written in the rule.</td><td>
                  Does that property reject the behavior you care about?
                </td>
              </tr>
              <tr>
                <td>A result about the translated code and model.</td><td>
                  Do the compiler, translator and outside services meet their own obligations?
                </td>
              </tr>
            </tbody>
          </table>
          <p>
            Consider a ledger that refuses every request. It can keep every total within the limits while doing none of the useful work. The positive-admission rule adds the promise that eligible requests actually succeed.
          </p>
          <p>
            Or consider an approved hold cancelled before confirmation. Its local counters could add up perfectly after an early release, while the payment service still holds the money. A rule about consistent counters alone does not forbid that transition.
          </p>
          <p>
            <.term key="lynx">Lynx</.term>
            translates compiled Elixir code and rules into Lean definitions and statements. Lean checks supplied proofs of those statements. The compiler and translation remain part of what you trust.
          </p>
          <details class="limits">
            <summary>Limits: things a pure proof does not establish</summary><p>
              A
              <.term key="journal">journal</.term>
              is the runtime's durable input log; its actual survival on disk depends on storage. The processor must give truthful reports, deduplicate requests and permanently refuse delayed authorization after terminal cancellation. Proofs about the pure model do not test a real bank, disk or network.
            </p>
          </details>
        </section>
        <section
          id="primer-alternatives"
          data-source="guides/interactive_review.md#a-pending-authorization-void;apps/review_web/lib/hold_ledger_review/dossier.ex#implication"
        >
          <h2>6. Why show you an alternative?</h2>
          <p>
            Reading correct code can make a weak rule look sufficient. Instead, take one situation and propose a different outcome: perhaps freeing money after a timeout. This
            <.term key="what_if">alternative</.term>
            lets you ask whether the rules would reject a mistake.
          </p>
          <p>
            Most starting alternatives imitate plausible bugs; they are invented examples, not observed failures. One starting alternative is deliberately correct. Your task is to judge the behavior, rather than assume every suggested change is bad.
          </p>
          <table>
            <thead>
              <tr>
                <th>You say</th><th>A tested rule catches it</th><th>No tested rule catches it</th>
              </tr>
            </thead><tbody>
              <tr>
                <td>Unacceptable</td><td>A named rule excludes this alternative here.</td><td>
                  A candidate gap among examined checks; the unexamined rules remain unknown.
                </td>
              </tr>
              <tr>
                <td>Acceptable</td><td>
                  Possible disagreement between the rule and intended policy; investigate.
                </td><td>You accept this local behavior; overall adequacy is still undecided.</td>
              </tr>
            </tbody>
          </table>
          <p>
            A
            <.term key="pointwise">single-example check</.term>
            calculates a rule on this concrete example. “No catch” may include rules that do not apply or cannot be checked here. It is a reason to investigate, not a proof that all rules permit the alternative.
          </p>
          <p>
            Decide what you think before revealing the rule results. Write your prediction in your own notes if that helps. The reveal flag records whether you looked before saving an answer; it does not record your private prediction or measure your honesty.
          </p>
        </section>
        <section
          id="primer-example"
          data-source="apps/review_web/priv/scenarios/P08.json;guides/specification.md#events;apps/review_web/lib/hold_ledger_review/dossier.ex#for_seed;apps/review_web/lib/hold_ledger_review/review_store.ex#conclusion_ready?"
        >
          <h2>7. What does one review look like?</h2>
          <p>
            Start with “Cancel before anything is sent” (P08). It teaches an important exception: cancelling a reservation that was never dispatched can release it immediately. That makes it a useful first case before the uncertain remote outcomes.
          </p>
          <dl class="worked-example">
            <div>
              <dt>Starting state</dt><dd>
                A local reservation holds 100 cents; nothing has been dispatched.
              </dd>
            </div><div>
              <dt>Event</dt><dd>Cancel that reservation.</dd>
            </div><div>
              <dt>Real result</dt><dd>
                Mark it cancelled, release 100 cents and one slot, request no outside work.
              </dd>
            </div><div>
              <dt>Alternative</dt><dd>The same result.</dd>
            </div>
          </dl>
          <p>
            An example answer is “Acceptable.” A reason could be: “This identity was never dispatched, so there is no issued authorization to wait for. Local cancellation may release the reservation.”
          </p>
          <p>
            After revealing, the supported checks either allow this example or do not apply; none catches it. That supports this local answer, not every cancellation policy. You still need to review the other questions and name what your conclusion covers.
          </p>
          <table>
            <thead>
              <tr>
                <th>Question</th><th>An example of what to consider</th>
              </tr>
            </thead><tbody>
              <tr>
                <td>Is the rule stated correctly?</td><td>
                  Does “eligible” include a request that fits exactly?
                </td>
              </tr><tr>
                <td>Is this alternative behavior OK?</td><td>
                  May this undispatched reservation release immediately?
                </td>
              </tr>
              <tr>
                <td>Is this evidence enough?</td><td>
                  Have you also examined cancellation after dispatch?
                </td>
              </tr><tr>
                <td>Should the rules cover more?</td><td>
                  Is an excluded input important to your service?
                </td>
              </tr><tr>
                <td>Do we trust the outside world here?</td><td>
                  What evidence shows the processor handles delayed requests safely?
                </td>
              </tr>
            </tbody>
          </table>
          <p>
            The first three questions are required before concluding; you may explicitly defer them with a reason. “Not sure” records uncertainty; “Defer” postpones the question and says what is missing. A positive conclusion also requires the otherwise optional questions resolved, saved evidence and no computed conflicts.
          </p>
          <p>
            For this introductory pass, you could conclude “Needs policy or evidence” and name the unresolved issued-hold or deployment questions. “Needs design change” records a disagreement with intended behavior. “Meets intent in reviewed scope” records agreement only within what you examined, once the remaining requirements are met.
          </p>
          <p>
            Confirming a conclusion locks the review. The Markdown or JSON export contains its scope, reasons, saved examples, answer history and open questions, ready to share with the policy owner or coding agent. Editing alone is temporary; saving an example or answering its behavior question stores it locally, and later answers keep earlier history.
          </p>
        </section>
        <section
          id="primer-ai"
          data-source="guides/agentic_verification.md#run-an-agent-through-a-bounded-change;guides/interactive_review.md#other-counterexamples"
        >
          <h2>8. Which AI are we talking about?</h2>
          <p>
            The coding agent can propose the code, rules and proofs you are reviewing. The optional AI helper in the decision pane has a different role: it can suggest questions or alternative examples for you to examine. It receives selected source and, for some requests, draft or review content only after you opt in for that request.
          </p>
          <p>
            You decide whether to accept a suggested question or save a proposed example. The helper cannot change your answer or certify a proof. You can complete a review without using it.
          </p>
        </section>
        <section
          id="primer-words"
          data-source="apps/review_web/lib/hold_ledger_review_web/glossary.ex#entries"
        >
          <h2>Ten words you'll see</h2>
          <table>
            <thead>
              <tr>
                <th>Word</th><th>Meaning here</th>
              </tr>
            </thead><tbody>
              <tr :for={key <- ~w(hold law lean lynx reducer oracle witness what_if pointwise pin)}>
                <td><.term key={key} /></td><td>{Glossary.one_line(key)}</td>
              </tr>
            </tbody>
          </table>
          <p>
            Use the header's plain-English dictionary whenever a word is unfamiliar. Each dotted-underlined term also opens a definition when you hover or focus it.
          </p>
        </section>
        <section
          id="primer-self-check"
          data-source="README.md#what-the-checks-establish;guides/interactive_review.md#evidence-and-limits"
        >
          <h2>Check your understanding</h2>
          <details>
            <summary>Who writes the proofs?</summary><p>
              A coding agent can draft them, and a person can too. Authorship does not establish that the statement is useful or that its proof was checked.
            </p>
          </details>
          <details>
            <summary>What does Lean check, and what does a proof leave open?</summary><p>
              Lean checks that a proof establishes its stated theorem under its assumptions. It does not choose the policy, establish every outside-world assumption, or decide that the rules cover everything you need.
            </p>
          </details>
          <details>
            <summary>Why does a timeout keep the money held?</summary><p>
              The processor may have approved the authorization even though its reply was lost. A missing reply is not reliable evidence of release.
            </p>
          </details>
          <details>
            <summary>What is an alternative for?</summary><p>
              It lets you test whether the examined rules reject a behavior you would reject, or reject one you would accept. It is a locally calculated example, not an observed processor outcome.
            </p>
          </details>
          <details>
            <summary>What are you deciding?</summary><p>
              Whether the reviewed rules and behavior match the intended policy within a scope you name. Your conclusion is a human judgment, separate from example checks and formal proof status.
            </p>
          </details>
        </section>
      </div>
    </details>
    """
  end

  attr :review, :map, required: true

  def briefing(assigns) do
    ~H"""
    <details
      id="scenario-briefing"
      class="briefing"
      open={@review["answers"] == [] && @review["pinned_probes"] == []}
      data-source="guides/specification.md#events;apps/review_web/priv/scenarios"
    >
      <summary>Before you start</summary>
      <p>{Glossary.briefing(@review["seed_id"])["why"]}</p>
      <h3>Two ideas to keep in mind</h3>
      <ul>
        <li>
          <.term key={Glossary.briefing(@review["seed_id"])["term1"]} />: {Glossary.briefing(
            @review["seed_id"]
          )["idea1"]}
        </li><li>
          <.term key={Glossary.briefing(@review["seed_id"])["term2"]} />: {Glossary.briefing(
            @review["seed_id"]
          )["idea2"]}
        </li>
      </ul>
      <p>
        Follow this part of the lifecycle: {Glossary.briefing(@review["seed_id"])["arrow"]} <a
          href="#scenario-lifecycle"
          phx-click={Phoenix.LiveView.JS.set_attribute({"open", ""}, to: "#scenario-lifecycle")}
        >Read the lifecycle below</a>.
      </p>
      <details id="scenario-lifecycle">
        <summary>The relevant lifecycle</summary><p>
          {Glossary.briefing(@review["seed_id"])["arrow"]}
        </p>
      </details>
      <h3>What the written policy says</h3><p>{Glossary.briefing(@review["seed_id"])["policy"]}</p>
      <h3>What to weigh</h3><ul>
        <li>{Glossary.briefing(@review["seed_id"])["weigh1"]}</li><li>
          {Glossary.briefing(@review["seed_id"])["weigh2"]}
        </li>
      </ul>
      <p>
        Read the four boxes left to right: starting state, event, real result, proposed alternative. Compare the amounts, hold count, entry statuses and requests for outside work. The rule results stay hidden until you reveal them.
      </p>
    </details>
    """
  end

  attr :review, :map, required: true
  attr :revealed, :boolean, required: true

  def coaching(assigns) do
    ~H"""
    <section
      id="step-coaching"
      class="step-coaching"
      aria-label="Review instructions"
      data-source="guides/interactive_review.md;apps/review_web/lib/hold_ledger_review_web/review_progress.ex#step"
    >
      <details
        :for={{key, number} <- Enum.with_index(~w(understand predict compare judge conclude), 1)}
        open={ReviewProgress.step(@review, @revealed) == number}
      >
        <summary>{number}. {Glossary.coach(key)["title"]}</summary>
        <p><b>Do now:</b> {Glossary.coach(key)["do"]}</p><p>
          <b>Look for:</b> {Glossary.coach(key)["look"]}
        </p><p><b>Done when:</b> {Glossary.coach(key)["done"]}</p>
      </details>
    </section>
    """
  end

  attr :current_card, :map, required: true

  def answer_help(assigns) do
    ~H"""
    <details
      id="answer-help"
      class="answer-help"
      data-source="apps/review_web/lib/hold_ledger_review/dossier.ex#implication"
    >
      <summary>What a good answer considers</summary>
      <p>{Glossary.answer_help(@current_card["kind"])["consider"]}</p>
      <p>
        <b>Example reason, not a suggested answer:</b> {Glossary.answer_help(@current_card["kind"])[
          "reason"
        ]}
      </p>
    </details>
    """
  end
end
