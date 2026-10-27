defmodule HoldLedgerReviewWeb.IndexLive do
  use HoldLedgerReviewWeb, :live_view
  def mount(_, _, socket), do: {:ok, assign(socket, :cases, HoldLedgerReview.Cases.all())}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="intro">
        <p class="eyebrow">Human-led formal verification</p><h1>
          What does the claim actually protect?
        </h1><p>
          Predict a transition. Try an unacceptable alternative. Inspect the guarantee and decide what the evidence supports.
        </p>
      </div>
      <div class="case-grid">
        <.link :for={c <- @cases} id={"case-"<>c.id} navigate={~p"/review/#{c.id}"} class="case-card">
          <span class="eyebrow">Practice case</span><h2>{c.title}</h2><p>{c.question}</p><span>Open workbench →</span>
        </.link>
      </div>
      <p class="boundary">
        Computed cases, original claims, checker reports and human judgments stay separate. No AI account is required.
      </p>
    </Layouts.app>
    """
  end
end
