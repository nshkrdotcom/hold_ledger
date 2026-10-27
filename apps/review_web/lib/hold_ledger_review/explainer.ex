defmodule HoldLedgerReview.Explainer do
  @moduledoc "Runs a bounded explanation request and validates its citations before display."
  alias HoldLedgerReview.{Anchor, Session}
  alias HoldLedgerReview.Explainer.{Inference, Scripted, Validator}

  def prompt,
    do:
      File.read!(
        Application.app_dir(:hold_ledger_review_web, "priv/prompts/review_explainer_v1.md")
      )

  def explain(packet, question, context) do
    if Session.text(question, 1000) == "" or
         not Map.has_key?(packet.facts.candidates, context.candidate) do
      {:error, :explainer_unavailable}
    else
      mode = Application.get_env(:hold_ledger_review_web, :explainer, :scripted)

      task =
        Task.Supervisor.async_nolink(HoldLedgerReview.Tasks, fn ->
          response(mode, packet, question, context)
        end)

      result =
        Task.yield(task, Application.get_env(:hold_ledger_review_web, :explainer_timeout, 15_000)) ||
          Task.shutdown(task, :brutal_kill)

      with {:ok, {:ok, data}} <- result, {:ok, items} <- Validator.validate(data, packet) do
        {:ok,
         %{
           mode: to_string(mode),
           items: items,
           packet_sha256: packet.packet_sha256,
           prompt_sha256: Anchor.sha(prompt()),
           model:
             if(mode == :scripted,
               do: "scripted",
               else:
                 Application.get_env(
                   :hold_ledger_review_web,
                   :inference_model,
                   "configured client"
                 )
             )
         }}
      else
        _ -> {:error, :explainer_unavailable}
      end
    end
  rescue
    _ -> {:error, :explainer_unavailable}
  end

  defp response(:scripted, packet, _question, context),
    do: {:ok, Scripted.response(packet, context)}

  defp response(:inference, packet, question, context),
    do: Inference.response(packet, question, context)

  defp response(_, _, _, _), do: {:error, :explainer_unavailable}
end
