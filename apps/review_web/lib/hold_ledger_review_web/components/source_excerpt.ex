defmodule HoldLedgerReviewWeb.SourceExcerpt do
  @moduledoc "Renders an original source excerpt with its location and digest."
  use Phoenix.Component
  attr :anchor, :map, required: true

  def source_excerpt(assigns) do
    ~H"""
    <article class="source-excerpt">
      <p>{@anchor.path}:{@anchor.line} · SHA256 {@anchor.sha256}</p>
      <pre><code>{@anchor.text}</code></pre>
    </article>
    """
  end
end
