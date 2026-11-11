defmodule HoldLedger.TestFixtures do
  @moduledoc "Independent literal, spec-valid test states; never built by the reducer."

  def zero, do: {0, 0, 0, 0, []}
  def empty, do: {1000, 3, 0, 0, []}
  def exact_fit, do: {100, 1, 0, 0, []}
  def full_slots, do: {1000, 1, 300, 1, [{11, 300, :reserved}]}
  def full_amount, do: {300, 2, 300, 1, [{11, 300, :sent}]}
  def full_both, do: {300, 1, 300, 1, [{11, 300, :unknown}]}
  def reserved, do: {1000, 3, 300, 1, [{11, 300, :reserved}]}
  def sent, do: {1000, 3, 300, 1, [{11, 300, :sent}]}
  def unknown, do: {1000, 3, 300, 1, [{11, 300, :unknown}]}
  def authorized, do: {1000, 3, 300, 1, [{11, 300, :authorized}]}
  def voiding, do: {1000, 3, 300, 1, [{11, 300, :voiding}]}
  def declined, do: {1000, 3, 0, 0, [{11, 300, :declined}]}
  def voided, do: {1000, 3, 0, 0, [{11, 300, :voided}]}

  def mixed do
    {1000, 4, 700, 3,
     [
       {11, 300, :sent},
       {12, 200, :unknown},
       {13, 200, :authorized},
       {14, 100, :declined},
       {15, 100, :voided}
     ]}
  end

  def with_status(:reserved), do: reserved()
  def with_status(:sent), do: sent()
  def with_status(:unknown), do: unknown()
  def with_status(:authorized), do: authorized()
  def with_status(:voiding), do: voiding()
  def with_status(:declined), do: declined()
  def with_status(:voided), do: voided()

  # Literal independent expectations for the experimental ordered-map reducer.
  # These fixtures are not computed by either reducer or by the Spec oracle.
  def map_boundary_cases do
    empty = {10, 1, 0, 0, []}
    reserved = {10, 1, 10, 1, [{1, 10, :reserved}]}
    sent = {10, 1, 10, 1, [{1, 10, :sent}]}
    unknown = {10, 1, 10, 1, [{1, 10, :unknown}]}
    authorized = {10, 1, 10, 1, [{1, 10, :authorized}]}
    voiding = {10, 1, 10, 1, [{1, 10, :voiding}]}
    voided = {10, 1, 0, 0, [{1, 10, :voided}]}
    declined = {10, 1, 0, 0, [{1, 10, :declined}]}

    [
      {empty, {:request, 1, 0}, empty, :malformed, []},
      {empty, {:request, 1, -1}, empty, :malformed, []},
      {empty, {:request, 1.0, 10}, empty, :malformed, []},
      {empty, {:request, :key, 10}, empty, :malformed, []},
      {empty, {:request, 1, 10.0}, empty, :malformed, []},
      {empty, {:request, 1, 10}, reserved, :admitted, []},
      {reserved, {:request, 1, 10}, reserved, :duplicate, []},
      {reserved, {:request, 1, 9}, reserved, :conflict, []},
      {reserved, {:request, 2, 11}, reserved, :insufficient_holds, []},
      {full_amount(), {:request, 99, 1}, full_amount(), :insufficient_amount, []},
      {reserved, {:dispatch, 1}, sent, :dispatched, [{:authorize, 1, 10}]},
      {sent, {:timeout, 1}, unknown, :marked_unknown, []},
      {sent, :restart, unknown, :restarted, []},
      {unknown, {:retry, 1}, sent, :retried, [{:authorize, 1, 10}]},
      {unknown, {:processor_result, 1, :approved}, authorized, :authorized, []},
      {sent, {:processor_result, 1, :declined}, declined, :declined, []},
      {unknown, {:processor_result, 1, :declined}, declined, :declined, []},
      {reserved, {:void, 1}, voided, :voided, []},
      {authorized, {:void, 1}, voiding, :voiding, [{:void, 1}]},
      {voiding, {:void_confirmed, 1}, voided, :voided, []},
      {voided, {:void_confirmed, 1}, voided, :stale, []},
      {voided, {:request, 1, 10}, voided, :duplicate, []},
      {voided, {:request, 1, 9}, voided, :conflict, []},
      {declined, {:request, 1, 10}, declined, :duplicate, []},
      {voided, {:request, 2, 5}, {10, 1, 5, 1, [{2, 5, :reserved}, {1, 10, :voided}]},
       :admitted, []},
      {reserved, {:void, 99}, reserved, :not_found, []},
      {sent, {:transport_ack, 1}, sent, :stale, []},
      {authorized, {:processor_result, 1, :approved}, authorized, :stale, []},
      {unknown, {:processor_result, 1, :bad}, unknown, :malformed, []},
      {reserved, {:dispatch, 1.0}, reserved, :malformed, []},
      {reserved, {:void_confirmed, :key}, reserved, :malformed, []},
      {reserved, {:unknown_event, %{key: 1}}, reserved, :malformed, []},
      {reserved, [:improper | :tail], reserved, :malformed, []},
      {mixed(), :restart,
       {1000, 4, 700, 3,
        [{11, 300, :unknown}, {12, 200, :unknown}, {13, 200, :authorized},
         {14, 100, :declined}, {15, 100, :voided}]}, :restarted, []}
    ]
  end

  def all do
    [
      zero(),
      empty(),
      exact_fit(),
      full_slots(),
      full_amount(),
      full_both(),
      reserved(),
      sent(),
      unknown(),
      authorized(),
      voiding(),
      declined(),
      voided(),
      mixed()
    ]
  end
end
