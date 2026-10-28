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

  @terms Map.merge(@terms, %{
           "formal_verification" =>
             {"Formal verification",
              "Using a mathematical proof to establish a precisely stated program property.",
              "A checked theorem covers its stated inputs and assumptions. Choosing the property and judging its adequacy remain separate tasks."},
           "pure" =>
             {"Pure calculation",
              "A calculation that returns values without performing outside work or changing hidden state.",
              "Ledger.step returns a next state, result and descriptions of effects. The runtime is responsible for I/O."},
           "runtime" =>
             {"Runtime",
              "The processes that record inputs and attempt the requested outside work.",
              "Its storage and processor assumptions need separate evidence from pure ledger proofs."}
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

  @briefings %{
    "P08" => %{
      "why" =>
        "This is the control example: the alternative matches the real local cancellation. Start here to separate an undispatched reservation from an issued authorization.",
      "term1" => "reserved",
      "idea1" => "No authorization has been dispatched for this reservation.",
      "term2" => "voided",
      "idea2" => "A cancelled local reservation no longer uses an amount or a slot.",
      "arrow" => "reserved → local cancellation → voided",
      "policy" =>
        "Voiding a reserved hold releases its amount and slot immediately and requests no outside work. The key remains remembered.",
      "weigh1" => "Was there an issued authorization whose outcome still needs confirmation?",
      "weigh2" => "Do the real result and the alternative differ in any field?",
      "teaches" => "Learn when immediate release is allowed.",
      "time" => "Allow 3–5 minutes."
    },
    "P04" => %{
      "why" =>
        "This example imitates refusing a request even though it fits exactly. It asks whether keeping within limits is enough.",
      "term1" => "capacity",
      "idea1" => "Both the amount limit and the hold-count limit must have room.",
      "term2" => "precondition",
      "idea2" =>
        "The admission rule applies to fresh positive requests that fit, including equality at the limit.",
      "arrow" => "fresh request → reserved",
      "policy" =>
        "A fresh positive request with a free slot and enough amount capacity must be admitted. An exact amount fit qualifies.",
      "weigh1" => "Is a request that fits exactly different from one that exceeds the limit?",
      "weigh2" =>
        "Would a ledger that refuses every request meet your intended service behavior?",
      "teaches" => "Learn why a safety limit also needs an admission promise.",
      "time" => "Allow 3–5 minutes."
    },
    "P01" => %{
      "why" =>
        "This alternative imitates releasing an approved hold as soon as cancellation is requested. It also omits the remote cancellation request.",
      "term1" => "authorized",
      "idea1" => "The processor has reported approval; the hold still uses capacity.",
      "term2" => "voiding",
      "idea2" => "Cancellation is pending, so asking to cancel is different from confirmation.",
      "arrow" => "authorized → void → voiding → trusted confirmation → voided",
      "policy" =>
        "Voiding an authorized hold keeps its amount and slot, marks cancellation pending and requests a remote void. Trusted confirmation releases it later.",
      "weigh1" =>
        "What could a second request do if capacity were released while the remote authorization still existed?",
      "weigh2" => "What outside work must still happen before the cancellation is complete?",
      "teaches" => "Separate a cancellation request from confirmed release.",
      "time" => "Allow 4–6 minutes."
    },
    "P05" => %{
      "why" =>
        "This alternative sends the cancellation request but releases capacity immediately. Compare it with the earlier cancellation example to isolate the retained-capacity question.",
      "term1" => "effects",
      "idea1" => "A returned void effect requests cancellation; it does not confirm it.",
      "term2" => "voiding",
      "idea2" => "Pending remote cancellation still counts against both limits.",
      "arrow" => "authorized → voiding, with capacity held → confirmation → voided",
      "policy" =>
        "An authorized hold becomes voiding and keeps its amount and slot while remote confirmation is pending.",
      "weigh1" => "What does emitting a request establish about the processor?",
      "weigh2" => "Could the amount be used again before the old authorization is safely gone?",
      "teaches" => "See why requesting outside work does not establish its completion.",
      "time" => "Allow 4–6 minutes."
    },
    "P03" => %{
      "why" =>
        "This alternative treats a timeout as a decline. It asks what the absence of a reply tells you about the processor.",
      "term1" => "sent",
      "idea1" => "Authorization was dispatched, but the ledger has no outcome yet.",
      "term2" => "unknown",
      "idea2" => "An unresolved outcome continues to use capacity.",
      "arrow" => "sent → timeout → unknown; retry returns unknown → sent with the same key",
      "policy" =>
        "Timeout changes a sent entry to unknown without releasing its amount or slot. It does not manufacture a processor decline.",
      "weigh1" => "Could the processor have approved before the reply was lost?",
      "weigh2" => "What evidence would distinguish a decline from silence?",
      "teaches" => "Separate missing information from evidence of failure.",
      "time" => "Allow 4–6 minutes."
    },
    "P06" => %{
      "why" =>
        "This alternative uses the unknown status but drops both reserved totals to zero. It tests whether the label and accounting agree.",
      "term1" => "unknown",
      "idea1" => "An unresolved authorization still counts as held.",
      "term2" => "validity",
      "idea2" => "The totals must equal the sum and count of the entries that are still held.",
      "arrow" => "sent → timeout → unknown, with both totals retained",
      "policy" =>
        "Timeout retains the unknown entry’s amount and slot. The used totals must still account for holding entries.",
      "weigh1" => "What should the amount and count report when the entry remains unknown?",
      "weigh2" => "Could a new request be admitted using totals that no longer count this hold?",
      "teaches" => "Compare status labels with the actual reserved totals.",
      "time" => "Allow 4–6 minutes."
    },
    "P02" => %{
      "why" =>
        "This alternative keeps the money reserved but omits the request to cancel it remotely. It separates accounting from the work still owed.",
      "term1" => "voiding",
      "idea1" => "Remote cancellation remains unfinished.",
      "term2" => "effects",
      "idea2" => "The outcome must describe required outside work as well as its next state.",
      "arrow" => "authorized → voiding, with a remote void request",
      "policy" =>
        "Voiding an authorized hold retains capacity and returns a request for remote cancellation.",
      "weigh1" => "What would cause the processor to learn about the cancellation?",
      "weigh2" => "Would correct counters alone be enough to describe the required transition?",
      "teaches" => "Look for required outside work, not just the next state.",
      "time" => "Allow 4–6 minutes."
    },
    "P07" => %{
      "why" =>
        "This alternative times out one hold while cancelling a different approved hold. The reduced counters are consistent with that unrelated cancellation.",
      "term1" => "identity",
      "idea1" =>
        "Each event names a particular key; other holds still have their own obligations.",
      "term2" => "unknown",
      "idea2" => "The timed-out sent hold keeps its amount and slot.",
      "arrow" => "hold 2: sent → unknown; hold 1 remains authorized",
      "policy" =>
        "Timeout changes the named sent entry to unknown. An unrelated approved hold remains held without its own release evidence.",
      "weigh1" => "Which entry does the event name, and which entries change in the alternative?",
      "weigh2" => "Could globally consistent totals hide an unauthorized change to another key?",
      "teaches" => "Check other identities as well as the event’s target.",
      "time" => "Allow 5–7 minutes."
    }
  }
  @coaching %{
    "understand" => %{
      "title" => "Understand the scenario",
      "do" =>
        "Read the briefing and four situation boxes. Follow one key from the starting state through the event.",
      "look" =>
        "The amount, hold count, status and requested outside work that differ between the real result and alternative.",
      "done" => "You can describe those differences without relying on the JSON."
    },
    "predict" => %{
      "title" => "Predict",
      "do" =>
        "Choose your answer before clicking “I’ve made my prediction.” Use your own notes if you want to keep a private prediction.",
      "look" =>
        "Whether you would accept the alternative under the stated policy, before knowing which rules catch it.",
      "done" =>
        "You have a provisional judgment and a reason. The app records whether you revealed first, not your private notes."
    },
    "compare" => %{
      "title" => "Compare with the laws",
      "do" =>
        "Reveal the rule results and read one row at a time: its plain rule, result and tested combinations of values.",
      "look" =>
        "Catches rejects the alternative here; Allows here accepts it at tested values; Doesn’t apply concerns a different case; Can’t check gives no answer. Tested N combinations says how many eligible parameter values were examined.",
      "done" =>
        "You can name the relevant catches and the checks that leave questions open. These are example results, not a proof run."
    },
    "judge" => %{
      "title" => "Judge",
      "do" =>
        "Use Acceptable or Unacceptable for the alternative; Not sure if you cannot decide; Defer with a reason if more work is needed.",
      "look" =>
        "An explanation tied to this example and policy. Save example only keeps evidence without judging it.",
      "done" =>
        "Your saved answer and its explanation appear under Latest. Answer the reading and evidence questions too; you can revise while the review is open."
    },
    "conclude" => %{
      "title" => "Conclude",
      "do" =>
        "Name the reviewed scope and your reason. Needs policy or evidence keeps uncertainty open; Needs design change records a mismatch; Meets intent in reviewed scope records agreement within that scope.",
      "look" =>
        "Unanswered questions, deferred work, computed conflicts and missing outside evidence. A positive conclusion requires all questions resolved and supporting evidence saved.",
      "done" =>
        "You explicitly confirm a conclusion, which locks the review. Export its Markdown or JSON record for the policy owner or agent."
    }
  }
  @answer_help %{
    "reading" => %{
      "consider" =>
        "Read the exact rule conditions and promised result. Check whether the plain reading includes the boundary you mean, such as an exact fit.",
      "reason" =>
        "“I read eligible as including equality at the amount limit; please keep that boundary explicit.”"
    },
    "escape" => %{
      "consider" =>
        "Compare the whole alternative with the starting state and event. Account for each key, both totals and any required outside work.",
      "reason" =>
        "“My concern is that a second request could use capacity while the first authorization still exists remotely.”"
    },
    "trace" => %{
      "consider" =>
        "Name the dimensions the examples examined and those they did not. One cancellation example does not address every possible history.",
      "reason" =>
        "“This example addresses local cancellation; I still need to examine a cancellation after dispatch.”"
    },
    "silence" => %{
      "consider" =>
        "Identify an input the rule excludes and why that case matters to the policy. An excluded input is not automatically a failed proof.",
      "reason" =>
        "“I want the policy owner to decide whether this excluded boundary belongs in the reviewed requirement.”"
    },
    "assumption" => %{
      "consider" =>
        "Ask who can provide evidence about storage and the actual processor. A model’s assumed promise is different from an observed deployment guarantee.",
      "reason" =>
        "“I need processor evidence that a cancelled identity cannot later be authorized by a delayed request.”"
    }
  }

  def briefing(seed), do: Map.fetch!(@briefings, seed)
  def coach(key), do: Map.fetch!(@coaching, key)
  def answer_help(kind), do: Map.fetch!(@answer_help, kind)

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
