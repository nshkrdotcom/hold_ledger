defmodule HoldLedgerReview.AI do
  @moduledoc """
  The sole configured Inference boundary for the workbench. No provider is
  chosen here: the installed client/adapter and model come from application
  configuration. Every outgoing request requires an explicit caller opt-in.
  """
  alias HoldLedgerReview.{AIPacket, AIProtocol}

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

  @doc "Fail closed if JSON-Schema capability is unsupported or unknown."
  def available?(opts \\ []) do
    try do
      client = Keyword.get_lazy(opts, :client, &client/0)
      supported =
        case Keyword.get(opts, :capability_check) do
          nil ->
            capabilities = Inference.capabilities(client)
            Inference.Capability.supported?(capabilities, :response_format_json_schema)

          check when is_function(check, 1) ->
            check.(client)
        end

      if supported == true do
        {:ok, client}
      else
        {:error, :ai_unavailable}
      end
    rescue
      _ -> {:error, :ai_unavailable}
    catch
      _, _ -> {:error, :ai_unavailable}
    end
  end

  def prepare(review, kind, card_id \\ nil, witness \\ nil),
    do: AIPacket.build(review, kind, card_id, witness)

  @doc "Send a prepared, explicitly consented request. No raw response is persisted."
  def run(packet, consent, opts \\ []) do
    if consent != true do
      {:error, :consent_required}
    else
      with {:ok, client} <- available?(opts),
           {:ok, request} <-
             Inference.Request.from_messages(
               [
                 %{role: :system, content: packet.system},
                 %{role: :user, content: packet.user}
               ],
               response_format:
                 {:json_schema,
                  %{name: "hold_ledger_#{packet.kind}", schema: AIProtocol.schema(packet.kind), strict: true}}
             ) do
        started = System.monotonic_time(:millisecond)

        case complete(client, request, opts) do
          {:ok, response} ->
            with {:ok, object} <- parse_response(response, packet.kind),
                 {:ok, checked} <- AIProtocol.validate(packet.kind, object, packet.context) do
              {:ok,
               Map.put(checked, "provenance", %{
                 "origin" => "model_proposed",
                 "latency_ms" => max(System.monotonic_time(:millisecond) - started, 0),
                 "prompt_sha256" => packet.prompt_hash,
                 "input_sha256" => packet.input_digest
               })}
            end

          {:error, error} ->
            {:error, classify(error)}
        end
      else
        {:error, :ai_unavailable} -> {:error, :ai_unavailable}
        {:error, error} -> {:error, classify(error)}
        _ -> {:error, :invalid_model_request}
      end
    end
  rescue
    _ -> {:error, :model_exception}
  catch
    _, _ -> {:error, :model_exception}
  end

  defp complete(client, request, opts) do
    case Keyword.get(opts, :complete) do
      nil -> Inference.complete(client, request)
      f when is_function(f, 2) -> f.(client, request)
    end
  end

  defp parse_response(%{tool_calls: calls}, _kind) when is_list(calls) and calls != [],
    do: {:error, :unexpected_tool_call}

  defp parse_response(response, kind) do
    value = Map.get(response, :object)

    data =
      if is_map(value) do
        {:ok, value}
      else
        text = Inference.Response.text(response)
        limit = if(kind == "deck", do: 32_768, else: 16_384)
        if is_binary(text) and byte_size(text) <= limit,
          do: Jason.decode(text),
          else: {:error, :invalid_model_output}
      end

    with {:ok, output} <- data,
         true <- is_map(output),
         true <- byte_size(Jason.encode!(output)) <= if(kind == "deck", do: 32_768, else: 16_384) do
      {:ok, output}
    else
      _ -> {:error, :invalid_model_output}
    end
  end

  defp classify(%Inference.Error{category: category}) when is_atom(category), do: category
  defp classify(error) when is_atom(error), do: error
  defp classify(_), do: :provider_failure
end
