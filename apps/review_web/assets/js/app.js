import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// The document owns source scrolling; mounting a proof never moves the page.
const ProofSource = {
  mounted() { this.stage = this.el.dataset.stage },
  updated() {
    if (this.stage === this.el.dataset.stage) return
    this.stage = this.el.dataset.stage
    this.el.querySelector(".active-proof-line")?.scrollIntoView({block: "start"})
  },
}

const InlineTools = {
  mounted() {
    this.opener = document.activeElement
    this.keydown = event => {
      if (event.key === "Escape") {
        event.preventDefault()
        this.pushEvent("close_tools", {})
      }
    }
    this.el.addEventListener("keydown", this.keydown)
  },
  destroyed() {
    this.el.removeEventListener("keydown", this.keydown)
    if (this.opener?.isConnected) this.opener.focus({preventScroll: true})
  },
}

window.addEventListener("phx:focus_evidence", ({detail}) => {
  requestAnimationFrame(() => {
    const panel = document.getElementById(detail.id)
    if (!panel) return
    panel.scrollIntoView({block: "start"})
    const target = panel.querySelector("summary") || panel
    if (target === panel) target.setAttribute("tabindex", "-1")
    target.focus({preventScroll: true})
  })
})

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {ProofSource, InlineTools},
})
topbar.config({barColors: {0: "#635080"}, shadowColor: "rgba(37,35,48,.2)"})
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())
liveSocket.connect()
window.liveSocket = liveSocket
