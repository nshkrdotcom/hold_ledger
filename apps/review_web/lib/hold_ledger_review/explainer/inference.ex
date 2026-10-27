defmodule HoldLedgerReview.Explainer.Inference do
  @moduledoc "Sends case evidence to an explicitly configured model that supports JSON Schema."
  alias HoldLedgerReview.{Canonical, Explainer}
  alias HoldLedgerReview.Explainer.Validator

  def response(p, question, context) do
    with {:ok, client} <- client(),
         capabilities when is_list(capabilities) <- Inference.capabilities(client),
         true <- Inference.Capability.supported?(capabilities, :response_format_json_schema),
         payload =
           Canonical.json(%{
             case_id: p.case.id,
             packet_sha256: p.packet_sha256,
             before: p.case.before,
             event: p.case.event,
             actual: p.facts.actual,
             oracle: p.facts.oracle,
             candidate: context.candidate,
             candidate_output: p.facts.candidates[context.candidate],
             predicates: p.facts.matrix[context.candidate],
             proof_status: p.proof.status,
             anchors: p.anchors,
             question: question
           }),
         true <- byte_size(payload) <= 200_000,
         {:ok, request} <-
           Inference.Request.from_messages(
             [
               %{role: :system, content: Explainer.prompt()},
               %{role: :user, content: payload}
             ],
             response_format:
               {:json_schema,
                %{
                  name: "ledger_review_v1",
                  schema: Validator.schema(Map.keys(p.anchors)),
                  strict: true
                }}
           ),
         {:ok, response} <- Inference.complete(client, request) do
      {:ok, response.object || Inference.Response.text(response)}
    else
      _ -> {:error, :explainer_unavailable}
    end
  end

  defp client do
    case Application.get_env(:hold_ledger_review_web, :inference_client) do
      %Inference.Client{} = client ->
        {:ok, client}

      _ ->
        {:error, :not_configured}
    end
  end
end
