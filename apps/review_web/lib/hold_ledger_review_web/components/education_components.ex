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
            Suppose you ask a coding agent to build a payment system. It proposes code, rules for that code, and proofs that the rules hold. You need to decide whether those rules describe the service you wanted.
          </p>
          <p>
            That decision belongs to you.
            <.term key="formal_verification">Formal verification</.term>
            means using a mathematical proof to show that a stated rule holds. For example, every request that fits the available limits must be admitted.
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
                  Checks whether a proof establishes the statement it was given.
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
            A proof answers the question in its statement. A ledger that refuses every request can keep its total at or below 100 cents. If you also want it to accept requests that fit, you need a rule saying so.
          </p>
          <p>
            You don’t need to read Lean to use this page. This app never runs Lean; it calculates examples and shows a separate proof report when one is attached.
          </p>
        </section>
        <section
          id="primer-ledger"
          data-source="README.md#the-ledger-in-a-few-steps;guides/specification.md#uncertain-outcomes-and-identities"
        >
          <h2>2. What is a payment hold?</h2>
          <p>
            Imagine a hotel reserving money on your card before it knows the final bill. The payment service could approve the reservation while its reply gets lost on the way back. The hotel still doesn’t know what happened.
          </p>
          <p>
            A
            <.term key="hold">hold</.term>
            reserves money. Hold Ledger records holds for one account and limits both their total amount in cents and their count. Each hold gets an integer <.term key="identity">key</.term>; the ledger keeps it after release, and retries use the same key and amount.
          </p>
          <ol>
            <li>Start with a 100-cent limit, room for two holds, and no money reserved.</li>
            <li>
              Request a 100-cent hold under key 11. The ledger admits it and reserves all 100 cents.
            </li>
            <li>
              Dispatch the authorization. The ledger returns a request for the payment service to authorize that hold.
            </li>
            <li>
              The request times out. The ledger marks it unknown and keeps the 100 cents reserved.
            </li>
            <li>
              Ask for another 100 cents under key 12. The ledger refuses: the first hold might still exist remotely.
            </li>
          </ol>
          <p>
            The ledger code is <.term key="pure">pure</.term>: it returns a next state and a list of outside work to request. Running this example moves no money. A hold that may have reached the processor stays counted until trusted evidence permits release; an undispatched reservation can be cancelled locally.
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
            Each arrow changes the ledger’s record. A request may be awaiting approval or cancellation confirmation even after it has been sent. A timeout keeps the money reserved because the service may have acted before the reply was lost.
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
            tells the ledger what happened or what to calculate next. The ledger accepts the events below; this page’s editor supports request, dispatch, timeout and void.
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
            describe outside work to request, such as authorizing or cancelling a hold. The
            <.term key="runtime">runtime</.term>
            attempts that work; a returned effect alone tells you nothing about whether the service received or completed it.
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
            states what the code must do. Its
            <.term key="precondition">requires</.term>
            part says when it applies; its
            <.term key="postcondition">expects</.term>
            part says what must follow. Here is the rule requiring the ledger to accept eligible requests, called <code>po_a2</code>.
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
            An empty account with a 100-cent limit must accept a fresh request for exactly 100 cents. Returning “insufficient amount” would break this rule. The reference model provides a comparison; you still choose the policy it should express.
          </p>
          <p>
            The ledger is written in <.term key="elixir">Elixir</.term>, a programming language. You can read the rule in words above or open its code below.
          </p>
          <details>
            <summary>Read the original rule in code</summary><pre phx-no-curly-interpolation>law(po_a2(s, key, amount),
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
            The catalog contains 49 rule groups, about fifty in all. Some address one operation; others address a sequence of events or a supporting model. Here are four more:
          </p>
          <ul>
            <li :for={slug <- ~w(po_exposure_retain po_b5_declined po_b6 po_b3)}>
              {Glossary.law_description(slug)} <small>{slug}</small>
            </li>
          </ul>
        </section>
        <section
          id="primer-proof"
          data-source="README.md#what-the-checks-establish;guides/formal_verification_crash_course.md#from-elixir-to-lean-with-lynx;guides/agentic_verification.md#compare-candidate-contracts"
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
            Compare two ledgers with a 100-cent limit. One accepts a fresh 100-cent request; the other refuses it. Both stay within the limit, but only the first meets the admission rule.
          </p>
          <p>
            Now suppose an approved hold releases its 100 cents before cancellation is confirmed. The local counters could still add up while the payment service holds the money. To forbid that change, a rule must require the hold to remain reserved until confirmation.
          </p>
          <p>
            <.term key="lynx">Lynx</.term>
            translates the compiled ledger code and its rules into Lean definitions and statements. Lean checks proofs of those statements. You still rely on the compiler that built the code and the translator that converted it.
          </p>
          <details class="limits">
            <summary>Limits: things a pure proof does not establish</summary><p>
              A
              <.term key="journal">journal</.term>
              records the runtime’s inputs so they can survive a restart; actual durability depends on storage. The processor must report truthfully, recognize repeated requests, and permanently reject delayed authorization for a terminally cancelled identity. A proof about the model does not test a real bank, disk or network.
            </p>
          </details>
        </section>
        <section
          id="primer-alternatives"
          data-source="guides/interactive_review.md#a-pending-authorization-void;apps/review_web/lib/hold_ledger_review/dossier.ex#implication"
        >
          <h2>6. Why show you an alternative?</h2>
          <p>
            A correct result does not show whether a rule would permit a bad one. Try changing the result, perhaps by freeing money after a timeout. That
            <.term key="what_if">alternative</.term>
            lets you ask whether the rules reject the mistake you have in mind.
          </p>
          <p>
            Most starting alternatives describe an invented mistake. P08 repeats the correct result, so you can practise accepting a behavior. None is an observed failure.
          </p>
          <table>
            <thead>
              <tr>
                <th>You say</th><th>A tested rule catches it</th><th>No tested rule catches it</th>
              </tr>
            </thead><tbody>
              <tr>
                <td>Unacceptable</td><td>A named rule rejects this alternative in this example.</td><td>
                  These checks leave a question open. Examine the remaining rules before calling it a gap.
                </td>
              </tr>
              <tr>
                <td>Acceptable</td><td>
                  Check whether the rule is too strict or the policy needs a decision.
                </td><td>
                  You accept this example. That alone does not show that the rules cover everything needed.
                </td>
              </tr>
            </tbody>
          </table>
          <p>
            A
            <.term key="pointwise">single-example check</.term>
            evaluates a rule on this example. Some rules may concern another situation or be beyond this tool’s checker. A missing catch leaves those rules undecided.
          </p>
          <p>
            Choose your answer before you reveal the rule results. You can jot a prediction in your own notes. The reveal flag records whether you looked before saving your answer; your private prediction stays in your notes.
          </p>
        </section>
        <section
          id="primer-example"
          data-source="apps/review_web/priv/scenarios/P08.json;guides/specification.md#events;apps/review_web/lib/hold_ledger_review/dossier.ex#for_seed;apps/review_web/lib/hold_ledger_review/review_store.ex#conclusion_ready?"
        >
          <h2>7. What does one review look like?</h2>
          <p>
            Start with “Cancel before anything is sent” (P08). Cancelling an undispatched reservation can release it immediately. Try this local case before tackling uncertain remote outcomes.
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
            After you reveal, the supported checks either allow this example or do not apply; none catches it. The result supports your answer for this case. The other questions help you decide what else needs review.
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
            Answer the first three questions before concluding, or defer them with a reason. Choose “Not sure” when you cannot decide, or “Defer” when the question needs later work. A positive conclusion also requires you to resolve the other questions, save supporting evidence and address any computed conflicts.
          </p>
          <p>
            For this introductory pass, you could conclude “Needs policy or evidence” and name the unresolved issued-hold or deployment questions. “Needs design change” records a disagreement with intended behavior. “Meets intent in reviewed scope” records agreement only within what you examined, once the remaining requirements are met.
          </p>
          <p>
            Confirming locks the review. You can export a Markdown document or JSON file with your conclusion, reasons, saved examples, answer history and open questions. Share it with the policy owner or coding agent; edits stay temporary until you save or answer, and revising an answer keeps its history.
          </p>
        </section>
        <section
          id="primer-ai"
          data-source="guides/agentic_verification.md#run-an-agent-through-a-bounded-change;guides/interactive_review.md#other-counterexamples"
        >
          <h2>8. Which AI are we talking about?</h2>
          <p>
            The coding agent can propose the code, rules and proofs under review. You can separately ask the optional AI helper in the decision pane to suggest questions or alternatives. Each send needs your consent: it shares selected source and, depending on the request, draft or review content.
          </p>
          <p>
            You choose whether to accept a question or save an example. The helper cannot change your answer or certify a proof. Using it is optional.
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
            <summary>What does Lean check, and what must you still decide?</summary><p>
              Lean checks that a proof establishes its stated rule under its assumptions. You still choose the policy, check the outside-world assumptions and judge whether the rules cover the situations you need.
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
      data-source={"guides/specification.md#events;apps/review_web/priv/scenarios/#{@review["seed_id"]}.json"}
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
      data-source="guides/interactive_review.md;apps/review_web/lib/hold_ledger_review_web/review_progress.ex#step;apps/review_web/lib/hold_ledger_review/review_store.ex#conclusion_ready?"
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
      <summary>What to consider in your answer</summary>
      <p>{Glossary.answer_help(@current_card["kind"])["consider"]}</p>
      <p>
        <b>An example reason:</b> {Glossary.answer_help(@current_card["kind"])[
          "reason"
        ]}
      </p>
    </details>
    """
  end
end
