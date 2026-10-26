defmodule HoldLedger.Processor do
  @moduledoc """
  Contract for the *assumed* external processor boundary. The in-process
  implementation is `HoldLedger.Processor.Sim`; it is not formally verified.

  An authorize response may be delivered, lost, delayed, or duplicated. A
  transport response is never proof of authorization to the pure ledger: only
  a journaled `{:processor_result, key, outcome}` makes that transition.
  """

  @type identity :: integer()
  @type outcome :: :approved | :declined
  @type reply ::
          {:ok, outcome()}
          | {:error, term()}
          | {:lost, :request | :reply}
          | {:delayed, non_neg_integer(), reply()}
          | {:callbacks, [outcome()]}

  @doc "Integrator-attested terminal semantics; startup checks shape, not truth."
  @callback capabilities(term()) :: %{
              terminal_confirmation: boolean(),
              non_resurrection: :permanent | :unsupported
            }

  @doc "Validate the declaration only; a lying adapter remains an external risk."
  def validate(nil), do: :ok

  def validate({module, context}) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :capabilities, 1) and
         module.capabilities(context) == %{
           terminal_confirmation: true,
           non_resurrection: :permanent
         },
       do: :ok,
       else: {:error, :missing_terminal_attestation}
  rescue
    _ -> {:error, :invalid_terminal_attestation}
  catch
    _, _ -> {:error, :invalid_terminal_attestation}
  end

  def validate(_), do: {:error, :invalid_processor}

  @callback authorize(term(), identity(), pos_integer()) :: reply()
  @callback lookup(term(), identity()) :: {:ok, outcome()} | :not_found | {:error, term()}
  @callback void(term(), identity()) :: {:ok, term()} | {:error, term()}
end
