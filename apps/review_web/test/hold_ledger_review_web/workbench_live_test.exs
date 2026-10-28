defmodule HoldLedgerReviewWeb.WorkbenchLiveTest do
  use HoldLedgerReviewWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias HoldLedgerReview.{Adversarial, ReviewStore}

  test "single workbench is the entrypoint and all old routes stay removed", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/workbench")
    assert html =~ "Decide what the ledger"
    assert html =~ "new-review-choices"

    for route <- ["/review", "/review/void_pending", "/review/receipts/fake"] do
      assert :error ==
               Phoenix.Router.route_info(HoldLedgerReviewWeb.Router, "GET", route, "localhost")
    end
  end

  test "loaded review contains focused cards, exact full witness, law matrix, graph and report links",
       %{conn: conn} do
    {:ok, doc, _witness} = ReviewStore.create("P06")
    {:ok, view, html} = live(conn, "/workbench/#{doc["id"]}")
    assert html =~ "Your judgment"
    assert html =~ "core.p06.escape"
    assert html =~ "catcher-matrix"
    assert html =~ "No follow-on event selected"
    assert html =~ "export.md"
    assert render_click(element(view, "#map-toggle")) =~ "design-map"
    assert render_click(element(view, "#source-toggle")) =~ "source-panel"
  end

  test "AI is visibly optional, and forged clicks without opt-in cannot enqueue jobs", %{
    conn: conn
  } do
    {:ok, doc, _} = ReviewStore.create("P01")
    {:ok, view, html} = live(conn, "/workbench/#{doc["id"]}")
    assert html =~ "configured inference service"
    assert has_element?(view, "#ai-deck[disabled]")
    assert has_element?(view, "#ai-challenge[disabled]")
    assert has_element?(view, "#ai-followup[disabled]")

    assert render_click(view, "ai_request", %{"kind" => "deck"}) =~
             "Explicit AI consent"

    assert {:ok, unchanged} = ReviewStore.get(doc["id"])
    assert unchanged["human_revision"] == doc["human_revision"]
    assert unchanged["ai_jobs"] == []
  end

  test "controlled prediction contradictions appear before model commentary and survive reload",
       %{conn: conn} do
    alias HoldLedgerReview.{AIPacket, AIProtocol}
    {:ok, review, _} = ReviewStore.create("P01")
    card = Enum.find(review["core_cards"], &(&1["kind"] == "escape"))
    {:ok, packet} = AIPacket.build(review, "deck", card["id"])
    token = fn -> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false) end
    job_id = token.()

    command = %{
      "request_id" => token.(),
      "expected_human_revision" => 0,
      "job_id" => job_id,
      "request_kind" => "deck",
      "prompt_hash" => packet.prompt_hash,
      "input_digest" => packet.input_digest,
      "source_digest" => packet.source_digest
    }

    {:ok, _} = ReviewStore.start_job(review["id"], command)
    {:ok, view, _} = live(conn, "/workbench/#{review["id"]}")

    object = %{
      "request_kind" => "deck",
      "target_node_id" => packet.context.target_node_id,
      "intent_hypotheses" => [],
      "card_suggestions" => [],
      "uncertainties" => [],
      "readings" => [
        %{
          "claim_slug" => "po_b1_void",
          "summary" => "Controlled contradicted reading",
          "not_claimed" => "No formal status or human judgment",
          "source_ids" => ["law.po_b1_void"],
          "predictions" =>
            Enum.map(Enum.take(Map.keys(packet.context.probes), 2), fn id ->
              %{
                "probe_id" => id,
                "predicted_status" => "catches",
                "explanation" => "Controlled incorrect prediction"
              }
            end)
        }
      ]
    }

    {:ok, checked} = AIProtocol.validate("deck", object, packet.context)

    output =
      Map.put(checked, "provenance", %{
        "origin" => "model_proposed",
        "latency_ms" => 0,
        "prompt_sha256" => packet.prompt_hash,
        "input_sha256" => packet.input_digest
      })

    assert {:ok, completed} =
             ReviewStore.complete_job(
               review["id"],
               Map.merge(
                 Map.take(command, ~w(job_id input_digest source_digest)),
                 %{"validated_output" => output, "error_class" => nil}
               )
             )

    assert hd(completed["ai_jobs"])["status"] == "complete"
    # The first result heading and the subsequent sibling enforce evidence-first order.
    assert has_element?(
             view,
             "#ai-job-#{job_id} .ai-results > h4:first-child",
             "Computed predictions"
           )

    assert has_element?(view, "#ai-job-#{job_id} .ai-results > ul + h4", "Model hypotheses")
    assert has_element?(view, "#ai-job-#{job_id} li", "prediction_conflicts")
    {:ok, reloaded, _} = live(conn, "/workbench/#{review["id"]}")
    assert has_element?(reloaded, "#ai-job-#{job_id} li", "prediction_conflicts")
    assert has_element?(reloaded, "#ai-consent:not([checked])")
    assert {:ok, ^completed} = ReviewStore.get(review["id"])
  end

  test "malformed latest draft never saves the preceding valid Escape probe", %{conn: conn} do
    {:ok, doc, witness} = ReviewStore.create("P04")
    {:ok, view, _} = live(conn, "/workbench/#{doc["id"]}")
    form = Adversarial.form(witness)

    assert render_change(view, "draft_changed", %{"draft" => Map.put(form, "output_json", "{")}) =~
             "draft-error"

    {:ok, after_change} = ReviewStore.get(doc["id"])
    assert after_change["pinned_probes"] == []
    assert after_change["answers"] == []
  end

  test "submit re-decodes the raw whole form before any change event", %{conn: conn} do
    {:ok, doc, witness} = ReviewStore.create("P04")
    {:ok, view, _} = live(conn, "/workbench/#{doc["id"]}")
    witness = put_in(witness, ["output", "after", "used_amount"], 99)
    raw = Adversarial.form(witness)

    view
    |> form("#candidate-form", %{"draft" => raw})
    |> render_submit(%{"draft" => %{"choice" => "unacceptable"}})

    {:ok, saved} = ReviewStore.get(doc["id"])
    assert hd(saved["pinned_probes"])["witness"] == witness
    assert hd(saved["answers"])["choice"] == "unacceptable"
    assert hd(saved["answers"])["probe_id"] == hd(saved["pinned_probes"])["id"]
    # A subsequent change is only an ephemeral draft; it cannot revise the committed answer.
    render_change(view, "draft_changed", %{"draft" => Map.put(raw, "output_json", "{")})
    assert has_element?(view, "#escape-acceptable[disabled]")
    assert has_element?(view, "#escape-unacceptable[disabled]")
    assert has_element?(view, "#escape-unsure[disabled]")
    assert render(view) =~ "Historical last-good evaluation only"
    assert {:ok, ^saved} = ReviewStore.get(doc["id"])

    view
    |> form("#candidate-form", %{"draft" => Map.put(raw, "output_json", "{")})
    |> render_submit(%{"draft" => %{"choice" => "unacceptable"}})

    assert {:ok, ^saved} = ReviewStore.get(doc["id"])
  end

  test "every known full source link returns the exact hashed file; unknown IDs fail", %{
    conn: conn
  } do
    alias HoldLedgerReview.{Anchor, Config}
    {:ok, doc, _} = ReviewStore.create("P01")

    for source <- doc["graph_snapshot"]["excerpts"] do
      response = get(conn, "/workbench/#{doc["id"]}/source/#{source["id"]}")
      bytes = response(response, 200)
      assert Anchor.sha(bytes) == source["sha256"]
      assert bytes == File.read!(Path.join(Config.root(), source["path"]))
    end

    assert response(get(conn, "/workbench/#{doc["id"]}/source/unknown"), 404)
  end

  test "reset and invalid drafts do not overwrite saved evidence or its implication", %{
    conn: conn
  } do
    alias HoldLedgerReview.Dossier
    {:ok, doc, witness} = ReviewStore.create("P01")
    {:ok, view, _} = live(conn, "/workbench/#{doc["id"]}")
    assert has_element?(view, "#scenario-brief", "Requests remote cancellation")
    view |> form("#candidate-form") |> render_submit(%{"draft" => %{"choice" => "unacceptable"}})
    {:ok, saved} = ReviewStore.get(doc["id"])
    card = Enum.find(saved["core_cards"], &(&1["kind"] == "escape"))

    {:ok, expected} =
      Dossier.implication(card, "unacceptable", hd(saved["pinned_probes"])["evaluation"])

    assert has_element?(view, "#latest-answer", expected)
    assert has_element?(view, ".progress-count", "1 of 3 required questions answered")

    render_change(view, "draft_changed", %{
      "draft" => Map.put(Adversarial.form(witness), "output_json", "{")
    })

    refute has_element?(view, "#scenario-brief .scenario-facts")
    assert has_element?(view, "#latest-answer", expected)
    render_click(element(view, "#reset-draft"))
    assert has_element?(view, "#scenario-brief .scenario-facts", "100¢ of 100¢")
    assert has_element?(view, "#candidate-ok")
    assert {:ok, ^saved} = ReviewStore.get(doc["id"])
  end

  test "all eight scenario summaries describe evaluated examples", %{conn: conn} do
    for seed <- Adversarial.seeds() do
      {:ok, doc, _} = ReviewStore.create(seed)
      {:ok, view, _} = live(conn, "/workbench/#{doc["id"]}")
      assert has_element?(view, "#scenario-brief .scenario-facts dd", "¢")
      assert has_element?(view, "#computed-contrast details summary", "Show raw JSON")
      assert has_element?(view, "#reset-draft")
    end
  end
end
