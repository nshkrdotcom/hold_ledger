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
