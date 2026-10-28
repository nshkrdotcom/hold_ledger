defmodule HoldLedgerReviewWeb.Glossary do
  @moduledoc "Shared display vocabulary. These explanations do not replace source claims or evidence."
  @terms %{
    "hold" =>
      {"Payment hold", "Money reserved while a payment decision is pending.",
       "This ledger models one account, an amount limit in integer cents and a limit on concurrent holds."},
    "reducer" =>
      {"Real ledger code",
       "The function that calculates the next state, result and requested outside work.",
       "Ledger.step takes the current state and an event. Calculating an effect does not perform the remote operation."},
    "oracle" =>
      {"Independent reference", "A separately written version of the intended transition rules.",
       "HoldLedger.Spec computes the expected result independently of Ledger. Agreement on examples is useful evidence, not a universal proof."},
    "spec" =>
      {"Reference model (Spec)",
       "The independent reference used to compare the real ledger with policy.",
       "Spec also defines predicates such as valid state, matching effects and retained exposure."},
    "law" =>
      {"Rule / law", "A precise statement with conditions and a promised result.",
       "A proof establishes the law as written under its conditions. Human review asks whether those conditions and promises match intended policy. PO means proof obligation."},
    "lean" =>
      {"Lean", "The proof checker used by the separate verification workflow.",
       "This web app does not run Lean. Its proof-status display requires an independently checked, source-matching report."},
    "lynx" =>
      {"Lynx", "The translator connecting the Elixir claims to Lean theorems.",
       "Its translation and the underlying compiler are part of the verification trust boundary."},
    "witness" =>
      {"Concrete example", "A complete starting state, event and proposed outcome.",
       "This workbench can also attach an optional next event to explore a consequence. The JSON editor describes this complete example."},
    "what_if" =>
      {"Proposed alternative", "An outcome you are being asked to judge against the real result.",
       "The alternative is checked locally against rule expressions. A follow-on may also be calculated from it. No remote payment operation is performed."},
    "pointwise" =>
      {"Single-example check",
       "A rule evaluated on one concrete example and its eligible values.",
       "Catches or Allows here describes only the tested example and bindings. It does not establish a Lean theorem or complete policy coverage."},
    "binding" =>
      {"Combination of values", "Concrete values assigned to the parameters of a rule.",
       "A rule may protect several holds, including a different key from the event key. The matrix says whether all eligible combinations were examined."},
    "pin" =>
      {"Save example", "Keep this example as evidence in the local review file.",
       "Ordinary editor changes stay temporary. Answering the alternative-behavior question saves that complete example and the answer together."},
    "card" =>
      {"Review question", "One question with its own stable identity and answer history.",
       "Required questions must be answered or explicitly deferred before concluding. AI suggestions become questions only after deliberate human acceptance."},
    "formal_checker" =>
      {"Independent proof report",
       "Evidence that a separate formal checker ran on matching source.",
       "This status is separate from local example checks and your judgment. A missing report is not a proof failure."},
    "effects" =>
      {"Requests for outside work",
       "Descriptions such as authorize this hold or request its cancellation.",
       "Effects are returned by the pure ledger. They do not establish delivery, approval or completed cancellation."},
    "capacity" =>
      {"Reserved capacity", "The amount and number of hold slots currently in use.",
       "Reserved, sent, unknown, authorized and voiding entries use capacity. Declined and voided entries do not."},
    "ast" =>
      {"Parsed source expression",
       "The structured representation of a rule read from source code.",
       "The example checker uses the original requires and expects expressions. It is not a model-written paraphrase."},
    "reading" =>
      {"Is the rule stated correctly?",
       "Compare the shown policy and rule with the intended requirement.",
       "Agreeing with a reading does not approve the policy as complete."},
    "escape" =>
      {"Is this alternative behavior OK?",
       "Judge the proposed outcome for the displayed starting state and event.",
       "An unwanted alternative may escape some rules while another rule catches it. This is a question about behavior, not proof compilation."},
    "silence" =>
      {"Should the rules cover more?",
       "Decide whether an excluded input situation should be covered.",
       "A false precondition is not a failed proof. An additional domain requirement needs an explicit policy decision."},
    "assumption" =>
      {"Do we trust the outside world here?",
       "Identify evidence for the processor or storage promises this design relies on.",
       "Pure proofs do not authenticate a real processor report or establish physical disk durability."},
    "trace" =>
      {"Is this evidence enough?",
       "Judge whether the examined evidence addresses the selected policy.",
       "The judgment applies only to named dimensions and examples, not all possible policy requirements."},
    "accurate" =>
      {"Matches the intended reading", "Record agreement with this reading of the rule.",
       "This is agreement with an interpretation, not general policy approval."},
    "inaccurate" =>
      {"Does not match", "Dispute the reading and explain the intended meaning.",
       "The correction remains a human judgment; no source rule is changed."},
    "unsure" =>
      {"Not sure", "Leave this question unresolved while recording your answer.",
       "Inspect the source, compare another example or ask the policy owner."},
    "deferred" =>
      {"Defer for later", "Postpone this question and keep it open in the export.",
       "Give a reason. An unresolved critical question prevents a positive conclusion."},
    "acceptable" =>
      {"Acceptable", "This alternative behavior is acceptable in this concrete situation.",
       "If a tested rule rejects it, investigate a possible policy/rule mismatch."},
    "unacceptable" =>
      {"Unacceptable", "This alternative behavior should be ruled out in this situation.",
       "Inspect which tested rules reject it. An untested remainder prevents a whole-policy conclusion."},
    "should_cover" =>
      {"Should cover this", "Record a candidate requirement to cover this situation.",
       "This proposes further policy work; it does not change a law or turn an excluded case into a failed proof."},
    "intentionally_excluded" =>
      {"Intentionally outside scope", "Record that this situation is deliberately excluded.",
       "Explain the scope decision so another reviewer can assess it."},
    "supported" =>
      {"Evidence supports it", "Record supporting evidence for this outside-world promise.",
       "Your answer does not authenticate or automatically attest the external service."},
    "disputed" =>
      {"I dispute this assumption", "Record a deployment promise that needs investigation.",
       "The review keeps this dependency unresolved."},
    "unknown" =>
      {"Unknown", "The outcome or supporting evidence has not been established.",
       "For a payment hold, an unknown outcome still consumes capacity. For a deployment question, unknown means evidence is still needed."},
    "sufficient_for_review" =>
      {"Enough for this review", "The evidence is sufficient within the named reviewed scope.",
       "This does not establish whole-policy completeness."},
    "gap_suspected" =>
      {"A gap needs investigation",
       "Record an open question about missing evidence or a requirement.",
       "A suspected gap is not automatically a confirmed implementation defect."},
    "pin_only" =>
      {"Save example only", "Save the example without answering whether it is acceptable.",
       "The review question remains unanswered."},
    "needs_policy_or_evidence" =>
      {"Needs policy or evidence", "We cannot settle the reviewed question yet.",
       "Confirming saves this scoped conclusion and locks the review. Open questions remain visible in the export."},
    "needs_design_change" =>
      {"Needs design change", "The reviewed rules or code disagree with intended behavior.",
       "This is a human conclusion for the stated scope, not an automatic defect verdict."},
    "meets_intent_in_reviewed_scope" =>
      {"Meets intent in reviewed scope",
       "Within what was examined, the rules match the intended policy.",
       "This is not universal adequacy, proof acceptance or deployment certification. Unresolved critical conflicts prevent this outcome."},
    "reserved" =>
      {"Reserved", "Admitted locally; authorization has not yet been dispatched.",
       "Uses an amount and a hold slot. A local void can release an undispatched reservation."},
    "sent" =>
      {"Sent", "Authorization was dispatched; no trusted outcome is known yet.",
       "Still consumes capacity. A timeout changes this entry to unknown, not declined."},
    "authorized" =>
      {"Authorized", "The processor reported approval.",
       "Consumes capacity. Asking to void starts cancellation; it does not finish it."},
    "voiding" =>
      {"Cancellation pending", "A void has been requested; remote confirmation is pending.",
       "Still consumes capacity until trusted terminal confirmation."},
    "declined" =>
      {"Declined", "The processor reported a decline; capacity is released.",
       "The identity and amount remain recorded. The key cannot be reused as a new hold."},
    "voided" =>
      {"Cancelled", "The hold is terminal and no longer consumes capacity.",
       "For an issued hold this requires terminal confirmation. An undispatched reservation can be cancelled locally. Its identity remains recorded."},
    "request" =>
      {"Request a hold", "Ask to reserve an amount under an integer key.",
       "A fresh eligible request must be admitted, including exact fits. Remembered keys produce duplicate or conflict results."},
    "dispatch" =>
      {"Dispatch authorization", "Describe an authorization request for a reserved hold.",
       "The returned authorize effect requests outside work. It does not mean the payment was approved."},
    "timeout" =>
      {"Timeout", "Mark a sent authorization as having an unknown outcome.",
       "The amount and slot remain in use."},
    "restart" =>
      {"Restart", "Mark recovered sent authorizations as unknown.",
       "Both accounting totals remain unchanged. Replay and the new restart event are distinct steps."},
    "retry" =>
      {"Retry authorization", "Try an unknown authorization using its original key and amount.",
       "A retry cannot create a fresh identity or release uncertain capacity."},
    "processor_result" =>
      {"Processor report", "An approved or declined result for an authorization.",
       "The runtime relies on authenticated, truthful reports from the processor."},
    "transport_ack" =>
      {"Delivery acknowledgment", "Acknowledge transport of a request.",
       "Delivery is not approval and cannot authorize a hold."},
    "void" =>
      {"Request cancellation",
       "Cancel a reserved hold locally or begin cancellation of an authorized hold.",
       "An authorized hold becomes voiding and retains capacity while confirmation is pending."},
    "void_confirmed" =>
      {"Cancellation confirmed", "Trusted terminal confirmation for a voiding hold.",
       "Releases its capacity once. Processor truthfulness and permanent fencing remain external assumptions."},
    "not_supplied" =>
      {"No proof report attached", "No independent Lean proof report is attached to this review.",
       "This tool checks examples against source rules; it does not run Lean."},
    "development_only" =>
      {"Development proof attempt",
       "A development proof result is supplied without full independent acceptance.",
       "Fresh exports and independent checker acceptance are separate evidence."},
    "selected_checked" =>
      {"Selected obligations checked",
       "The report supports checked acceptance for a selected source-matching subset.",
       "This does not establish full-catalog acceptance or policy adequacy."},
    "full_catalog_checked" =>
      {"Full catalog checked",
       "The attached source-matching report supports the complete required catalog.",
       "This is formal acceptance within the report scope and assumptions, not whole-system or policy certification."},
    "incomplete" =>
      {"Evidence incomplete", "Required report evidence is missing or could not be validated.",
       "Do not treat an incomplete result as a checked proof."},
    "stale" =>
      {"Evidence out of date", "The evidence does not match the current source or context.",
       "Rebuild and create a review on the current source before relying on new results."},
    "in_progress" =>
      {"In progress", "This review can still accept your answers.",
       "Editing alone is not a save. Use an answer or Save example to persist evidence."},
    "review_concluded" =>
      {"Concluded · read only", "A human confirmed the scoped conclusion.",
       "Start another review to investigate a new question."},
    "stale_read_only" =>
      {"Out of date · read only",
       "The code, rules or proof-report identity changed after this review began.",
       "The saved history is preserved. Rebuild as necessary and start a new review to keep evaluating."},
    "corrupt_read_only" =>
      {"Unreadable review", "The saved review cannot be safely interpreted.",
       "No approval is inferred from unreadable data. Keep the file for inspection and start a new review."},
    "pending" =>
      {"Waiting for AI", "An explicitly requested model job is pending.",
       "Completion is stored independently of the browser connection. There is no automatic resend."},
    "complete" =>
      {"AI response received", "A structured response passed the local checks.",
       "The response remains an AI proposal; it does not become a human answer or proof verdict."},
    "failed" =>
      {"Request or check failed", "This operation did not produce accepted evidence.",
       "Inspect the technical details. An AI request needs a fresh opt-in to retry."},
    "interrupted" =>
      {"Interrupted · retry manually", "The process restarted before the job completed.",
       "No automatic resend occurs. Opt in again only if you want another request."},
    "discarded_late" =>
      {"Outdated response discarded",
       "The result arrived after its source or human context changed.",
       "It cannot overwrite your later answer. A retry requires a new explicit request."},
    "catches" =>
      {"Catches", "This rule rejects the alternative for the tested example.",
       "It is a pointwise counterfactual check, not a proof about another program."},
    "allows_here" =>
      {"Allows here", "This rule accepts the alternative at the tested values.",
       "This does not establish that every rule permits it or that the behavior is desirable."},
    "does_not_apply" =>
      {"Doesn’t apply",
       "This rule concerns a different situation or has no eligible values here.",
       "See the exact preconditions and tested domain. Out-of-operation rules are not treated as failed preconditions."},
    "cant_check" =>
      {"Can’t check", "This tool could not evaluate the rule for this example.",
       "Unsupported shape, incomplete values, source drift and evaluation errors remain distinct diagnostics."},
    "prediction_matches" =>
      {"Prediction matches", "The model prediction matches the computed label for this example.",
       "This does not certify its prose interpretation."},
    "prediction_conflicts" =>
      {"Prediction contradicted", "The computed label disagrees with the model prediction.",
       "Read the computed example before considering the model commentary."},
    "cannot_evaluate" =>
      {"Prediction cannot be checked", "There is no usable computed label for this prediction.",
       "Do not count this as a matching prediction."},
    "probe" =>
      {"Saved or draft example check",
       "A concrete input and alternative checked against selected rules.",
       "A draft becomes saved evidence only through an explicit save or answer."},
    "identity" =>
      {"Request identity", "The integer key and original amount identifying a hold.",
       "Identity is remembered after release. Retries retain it and terminal keys cannot allocate again."},
    "domain" =>
      {"When a rule applies", "The inputs and parameter values allowed by its preconditions.",
       "A rule makes no promise outside this domain."},
    "precondition" =>
      {"Required conditions", "The conditions under which a law makes its promise.",
       "Written as requires in the source."},
    "postcondition" =>
      {"Promised result", "What the law requires after an operation when its conditions hold.",
       "Written as expects in the source."},
    "journal" =>
      {"Durable input log",
       "The runtime records and synchronizes an input before applying it or sending effects.",
       "Actual storage durability remains a hardware and operating-system assumption."},
    "fencing" =>
      {"Permanent terminal fencing",
       "The processor must refuse delayed authorization for a terminally cancelled identity.",
       "A declaration of this capability is not evidence that a real processor honors it."},
    "sha256" =>
      {"Content fingerprint", "A digest used to detect changes in source or evidence.",
       "A matching fingerprint identifies bytes; it is not a correctness proof."},
    "core_erlang" =>
      {"Core Erlang",
       "The compiled intermediate representation used by the translation pipeline.",
       "The web workbench does not run that proof pipeline."},
    "dsl" =>
      {"Elixir law declaration",
       "A requires/ expects statement written in the project’s law notation.",
       "Some catalog obligations are native Lean declarations and have no single-example adapter here."},
    "native_lean" =>
      {"Lean-only obligation", "A formal declaration outside this tool’s single-example checker.",
       "Its catalog entry does not itself show that a proof run succeeded."}
  }
  @terms Map.merge(@terms, %{
           "json" =>
             {"Typed JSON", "Text describing a state, event or outcome with named fields.",
              "The editor accepts the exact shapes shown in its starting example. Numbers are integer cents or counts, quoted words are fixed labels, and null means no next event."},
           "event" =>
             {"Event", "An input that asks the ledger to calculate its next transition.",
              "The example editor supports request, dispatch, timeout and void. The wider ledger also handles processor reports, confirmations and recovery events."},
           "result" =>
             {"Local result", "The ledger's label for the outcome of this input.",
              "Results describe the local calculation. Effects separately describe requests for work outside the ledger."},
           "validity" =>
             {"Valid ledger state",
              "A state satisfying the reference model's structural and accounting constraints.",
              "Validity alone can permit an unwanted transition. Admission, required effects and retained exposure are separate requirements."},
           "terminal" =>
             {"Terminal hold",
              "A declined or cancelled identity that cannot become active again.",
              "Its remembered key and amount remain in the ledger after capacity is released."},
           "processor" =>
             {"Payment processor",
              "The outside service that approves authorizations and confirms cancellations.",
              "Its truthful reports, identity deduplication and permanent terminal fencing are outside-world assumptions."},
           "deck" =>
             {"Discover questions",
              "Ask the AI to read selected source and suggest questions or competing interpretations.",
              "Locally computed synthetic checks verify any model predictions. Suggestions require explicit human acceptance."},
           "challenge" =>
             {"Propose an alternative",
              "Ask the AI for a complete typed example to test locally.",
              "A validated proposal can be loaded as a temporary draft. Loading it does not save it or answer its question."},
           "followup" =>
             {"Challenge my answer",
              "Ask the AI about the selected question's latest saved answer and evidence.",
              "The request includes recorded revision history and the prior validated model question, if present. It does not change your answer."}
         })

  @laws %{
    "l1_find" => "Looking up a unique entry agrees with the independent reference.",
    "l2_identity" => "Changing a status keeps every recorded key and amount.",
    "l3_accounting" =>
      "Changing a holding status adjusts amount and count by exactly that entry.",
    "l4_structure" => "Replacing a status keeps entries well formed and keys unique.",
    "l5_fresh" => "Adding a fresh reservation consumes its amount and exactly one slot.",
    "l6_restart" => "Changing sent entries to unknown retains both totals.",
    "po_i" => "Initialization produces a valid ledger for nonnegative limits.",
    "po_a1" => "A request preserves a valid ledger state.",
    "po_a2" => "Every eligible request, including an exact fit, must be admitted exactly.",
    "po_a3" => "An unapplied event leaves the state unchanged and requests no outside work.",
    "po_a4_duplicate" => "A remembered key requested at its original amount is a duplicate.",
    "po_a4_conflict" =>
      "A remembered key requested at a different positive amount is a conflict.",
    "po_b1_dispatch" => "Dispatch preserves a valid ledger state.",
    "po_b1_timeout" => "Timeout preserves a valid ledger state.",
    "po_b1_restart" => "Restart preserves a valid ledger state.",
    "po_b1_retry" => "Retry preserves a valid ledger state.",
    "po_b1_processor_result" => "A processor report preserves a valid ledger state.",
    "po_b1_void" => "Cancellation preserves a valid ledger state.",
    "po_b2" => "An already unknown identity stays unknown or sent until its own result.",
    "po_b3" => "Requested outside work must agree with stored identities and the result.",
    "po_s" => "One arbitrary event preserves a valid ledger state.",
    "po_c1" => "Every proper finite event list preserves a valid state.",
    "po_c2" => "Every modeled journal prefix from initialization is valid.",
    "po_b4" => "First authorization requires an approved result for that key.",
    "po_b5_declined" => "A declined key remains declined after every next event.",
    "po_b5_voided" => "A cancelled key remains cancelled after every next event.",
    "po_b6" => "Every previously seen key and amount remains recorded.",
    "po_b7" => "Restart removes sent statuses without reducing reserved totals.",
    "po_c3" =>
      "Finite histories agree with the reference and retain identity and terminal outcomes.",
    "po_b1_void_confirmed" => "Cancellation confirmation preserves a valid ledger state.",
    "po_attempt_poison" => "A poisoned attempt lifecycle refuses new attempts.",
    "po_terminal_fence" => "A terminal processor fence rejects delayed authorization.",
    "po_attempt_retired" =>
      "An absent attempt ignores late completion, deadline and shutdown signals.",
    "po_attempt_slot" => "An occupied operation/key slot refuses another start.",
    "po_exposure_retain" =>
      "An issued identity stays held without its own terminal release evidence.",
    "po_composite_recovery" =>
      "Committed transitions replay to the same ledger and pending-work state.",
    "po_exposure_history" =>
      "Issued identities retain capacity through histories without terminal evidence.",
    "po_exposure_bounds" =>
      "Remote exposure stays within limits under the stated processor assumptions.",
    "po_attempt_history" =>
      "Typed attempt histories preserve unique identities and retire each attempt at most once.",
    "po_composite_init" => "Initialization creates a valid ledger and pending-work state.",
    "po_composite_preservation" =>
      "A composite transition preserves the ledger and pending-work relationship.",
    "po_composite_oracle" => "Composite transitions agree with the independent reference.",
    "po_composite_history" => "Finite composite histories preserve their modeled guarantees.",
    "po_composite_confirmation" =>
      "Terminal confirmation releases capacity and removes the pending void together.",
    "po_composite_open" => "Opening pending void work preserves the composite relationship.",
    "po_composite_recovery_valid" => "Composite recovery preserves validity.",
    "po_exposure_model" =>
      "The ledger and modeled processor remain in a consistent exposure relationship.",
    "po_exposure_model_bounds" => "The exposure model stays within amount and hold-count limits.",
    "po_attempt_persist" => "Attempt persistence preserves the modeled lifecycle guarantees."
  }
  @scenarios %{
    "P01" =>
      {"Cancel an approved hold", "May capacity be released before cancellation is confirmed?",
       "A 100¢ hold was approved. You ask to cancel it. The ledger keeps 100¢ and one slot reserved while cancellation is pending.",
       "An approved hold uses 100¢ of a 100¢ limit.", "Request cancellation for hold 1.",
       "Keep 100¢ reserved; mark cancellation pending; request a remote void.",
       "Release all capacity immediately and mark the hold cancelled, with no void request."},
    "P02" =>
      {"A cancellation request goes missing",
       "Is keeping the money reserved enough if no void request is emitted?",
       "An approved 100¢ hold is being cancelled. The proposed outcome keeps the reservation but omits the request to the processor.",
       "An approved hold uses 100¢.", "Request cancellation for hold 1.",
       "Retain capacity and request a remote void.",
       "Keep capacity reserved, but request no outside work."},
    "P03" =>
      {"No reply from the processor", "Can silence be treated as a decline?",
       "An authorization request was sent, but no outcome arrived. The real ledger marks it unknown and retains capacity.",
       "A sent hold uses all 100¢ of available capacity.", "A timeout occurs for hold 1.",
       "Mark the result unknown; keep 100¢ and one slot reserved.",
       "Treat the timeout as a decline and free the capacity."},
    "P04" =>
      {"A request fits exactly", "Must a request that exactly fits be admitted?",
       "An empty account has a 100¢ limit and one free hold slot. A fresh request asks for exactly 100¢.",
       "No holds; 100¢ and one slot available.", "Request a new 100¢ hold.",
       "Admit the request and reserve 100¢ plus one slot.",
       "Refuse for insufficient amount, leaving capacity unused."},
    "P05" =>
      {"A void request with early release",
       "Does sending a void request justify releasing the money now?",
       "An approved hold is being cancelled. The alternative emits a void request but frees the capacity before confirmation.",
       "An approved hold uses 100¢.", "Request cancellation for hold 1.",
       "Keep capacity reserved while the void is pending.",
       "Send a void request and immediately release all capacity."},
    "P06" =>
      {"Unknown, but no money held", "Can the counters say free while a hold is still unknown?",
       "A sent request times out. The alternative marks the entry unknown but drops the reserved totals to zero.",
       "A sent hold uses 100¢ and one slot.", "A timeout occurs.",
       "Mark unknown and retain the amount and slot.",
       "Keep the unknown entry but report zero reserved amount and holds."},
    "P07" =>
      {"A timeout touches another hold",
       "Should a timeout release a different, already approved hold?",
       "Two holds reserve 150¢: one approved for 50¢ and one sent for 100¢. The alternative cancels the unrelated approved hold while timing out the sent one.",
       "Two holds use 150¢ and two slots.", "The 100¢ sent hold times out.",
       "Keep both holds and all 150¢ reserved.",
       "Cancel the other 50¢ hold, leaving only 100¢ and one slot reserved."},
    "P08" =>
      {"Cancel before anything is sent",
       "Is immediate release correct for an undispatched reservation?",
       "This 100¢ hold is reserved locally and has never been dispatched. Cancelling it locally releases capacity; the proposed outcome matches the real result.",
       "An undispatched reservation uses 100¢.", "Cancel the local reservation.",
       "Mark cancelled and release its amount and slot; no remote work is needed.",
       "The same local cancellation and capacity release."}
  }

  def entries, do: Enum.sort_by(@terms, fn {_key, {label, _, _}} -> String.downcase(label) end)
  def entry(key), do: Map.get(@terms, key)

  def label(key) do
    case entry(key) do
      {label, _, _} -> label
      nil -> key |> String.replace("_", " ") |> String.capitalize()
    end
  end

  def one_line(key) do
    case entry(key) do
      {_, text, _} -> text
      nil -> "See the attached source and technical details."
    end
  end

  def anchor(key), do: "glossary-" <> String.replace(key, ~r/[^a-zA-Z0-9-]/, "-")
  def law_description(slug), do: Map.get(@laws, slug, "No description yet")
  def law_slugs, do: Map.keys(@laws)
  def scenarios, do: @scenarios |> Map.keys() |> Enum.sort()
  def scenario(id), do: Map.fetch!(@scenarios, id)
  def scenario_title(id), do: scenario(id) |> elem(0)
  def scenario_question(id), do: scenario(id) |> elem(1)

  def source_title("guides/specification.md"), do: "Payment policy"
  def source_title("lib/hold_ledger/ledger.ex"), do: "Real ledger code"
  def source_title("lib/hold_ledger/spec.ex"), do: "Independent reference model"
  def source_title("guides/" <> _), do: "Design and operational guidance"

  def source_title("test/laws/" <> name),
    do: name |> String.replace_suffix("_test.exs", "") |> law_description()

  def source_title("test/support/lean/" <> _), do: "Formal declaration and proof source"
  def source_title("verification/laws.json"), do: "Registered rule catalog"
  def source_title("verification/obligations.json"), do: "Required formal obligations"
  def source_title(_), do: "Referenced source"

  def review_title(review) do
    case review["target_policy_nodes"] do
      ["policy.events.14" | _] -> "Cancellation of an approved hold"
      ["policy.events.13" | _] -> "Cancellation of a local reservation"
      ["policy.events.07" | _] -> "Authorization timeout"
      ["policy.events.01" | _] -> "Admission of a new hold"
      _ -> "Saved policy review"
    end
  end

  def error(reason) when is_tuple(reason), do: reason |> elem(0) |> error()

  def error(reason) when reason in [:human_revision_conflict, :stale_human_revision],
    do: "Another tab changed this review. Reload it, inspect the saved answer, then try again."

  def error(reason) when reason in [:stale_source, :source_or_compiled_code_drift],
    do: "The code or rules changed. Rebuild and start a new review on the current source."

  def error(:defer_reason_required), do: "Add a reason before deferring this question."

  def error(:unresolved_critical_conflict),
    do:
      "Resolve open questions and computed conflicts, and save supporting evidence before a positive conclusion. Otherwise choose Needs policy or evidence."

  def error(:unanswered_mandatory_or_critical),
    do: "Answer or explicitly defer the required questions before concluding."

  def error(:mandatory_questions_open),
    do: "Answer or explicitly defer the required questions before concluding."

  def error(:review_closed),
    do: "This review has been concluded and is read only. Start a new review to keep evaluating."

  def error(:correction_required),
    do: "Explain what the reading gets wrong before saving this disagreement."

  def error(:supporting_evidence_required),
    do: "Save an example as supporting evidence before confirming this conclusion."

  def error(:invalid_answer),
    do:
      "Use an offered answer and a reason of at most 600 characters. Your previous answer remains saved."

  def error(:invalid_conclusion),
    do: "Choose an offered outcome and give a scope and rationale before confirming."

  def error(:write_failed),
    do:
      "The local review file could not be saved. Check the file permissions and available space, then try again."

  def error(:read_only), do: "This review is read only. Start a new review to keep evaluating."
  def error(:invalid_choice), do: "Choose one of the answers offered for this question."

  def error(:invalid_draft),
    do: "The submitted example could not be read. Correct the JSON fields and submit again."

  def error(:ai_unavailable),
    do: "The configured AI service is unavailable. Local checks and your review remain available."

  def error(:consent_or_revision_required),
    do: "Opt in for this request and reload if another tab changed the review."

  def error(_),
    do:
      "The operation was not saved. Check the technical details, correct the input or reload the review, then try again."
end
