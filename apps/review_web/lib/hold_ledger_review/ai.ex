defmodule HoldLedgerReview.AI do
  @moduledoc """
  The sole configured Inference boundary for the workbench. No provider is
  chosen here: the installed client/adapter and model come from application
  configuration. Every outgoing request requires an explicit caller opt-in.
  """

  @app :hold_ledger_review_web

  def client do
    options = Application.fetch_env!(@app, :inference_client_options)

    options =
      if model = Application.get_env(@app, :inference_model),
        do: Keyword.put(options, :model, model),
        else: options

    options =
      if effort = Application.get_env(@app, :inference_reasoning_effort) do
        Keyword.update(options, :defaults, [reasoning_effort: effort], fn current ->
          Keyword.put(current, :reasoning_effort, effort)
        end)
      else
        options
      end

    Inference.Client.new!(options)
  end

  @doc "The question profile uses the configured adapter with the explicit question model."
  def question_client do
    options = Application.fetch_env!(@app, :inference_client_options)

    options
    |> Keyword.put(:model, "gpt-6.1-terra")
    |> Keyword.update(
      :defaults,
      [reasoning_effort: :medium],
      &Keyword.put(&1, :reasoning_effort, :medium)
    )
    |> Inference.Client.new!()
  end

  def answer(packet, consent, opts \\ [])

  def answer(packet, true, opts) do
    with :ok <- HoldLedgerReview.QuestionContext.freshness(packet),
         {:ok, client} <- available?(Keyword.put(opts, :client, question_client())),
         {:ok, request} <-
           Inference.Request.from_messages(packet["messages"],
             response_format:
               {:json_schema,
                %{
                  name: "hold_ledger_question",
                  schema: HoldLedgerReview.QuestionContext.schema(),
                  strict: true
                }}
           ),
         {:ok, response} <- complete(client, request, opts) do
      question_answer(response, packet)
    else
      {:error, reason} -> {:error, classify(reason)}
    end
  rescue
    _ -> {:error, :model_exception}
  end

  def answer(_, _, _), do: {:error, :consent_required}

  defp question_answer(%{tool_calls: calls}, _) when is_list(calls) and calls != [],
    do: {:error, :unexpected_tool_call}

  defp question_answer(response, packet) do
    with {:ok, object} <- question_object(response),
         {:ok, answer} <- HoldLedgerReview.QuestionContext.validate_answer(object, packet) do
      {:ok, answer, response_metadata(response)}
    else
      _ ->
        {:error,
         %{"kind" => "invalid_answer", "visible_completion" => public_completion(response)}}
    end
  end

  defp response_metadata(response) do
    %{
      "routing_evidence" => "adapter_response_metadata",
      "response_model" => Map.get(response, :model),
      "response_provider" => provider_name(Map.get(response, :provider)),
      "response_id" => Map.get(response, :id)
    }
  end

  defp provider_name(nil), do: nil
  defp provider_name(provider) when is_atom(provider), do: Atom.to_string(provider)
  defp provider_name(provider) when is_binary(provider), do: provider

  defp public_completion(%{object: object}) when is_map(object),
    do: String.slice(Jason.encode!(object), 0, 16_384)

  defp public_completion(response), do: String.slice(Inference.Response.text(response), 0, 16_384)

  defp question_object(%{object: object}) when is_map(object), do: {:ok, object}

  defp question_object(response) do
    text = Inference.Response.text(response)

    if byte_size(text) <= 65_536,
      do: Jason.decode(text),
      else: {:error, :invalid_answer}
  end

  @doc "Fail closed if JSON-Schema capability is unsupported or unknown."
  def available?(opts \\ []) do
    client = Keyword.get_lazy(opts, :client, &client/0)

    supported =
      case Keyword.get(opts, :capability_check) do
        nil ->
          capabilities = Inference.capabilities(client)
          Inference.Capability.supported?(capabilities, :response_format_json_schema)

        check when is_function(check, 1) ->
          check.(client)
      end

    if supported == true, do: {:ok, client}, else: {:error, :ai_unavailable}
  rescue
    _ -> {:error, :ai_unavailable}
  catch
    _, _ -> {:error, :ai_unavailable}
  end

  defp complete(client, request, opts) do
    case Keyword.get(opts, :complete) do
      nil -> Inference.complete(client, request)
      f when is_function(f, 2) -> f.(client, request)
    end
  end

  defp classify(%Inference.Error{category: category}) when is_atom(category), do: category
  defp classify(error) when is_atom(error), do: error
  defp classify(_), do: :provider_failure
end
