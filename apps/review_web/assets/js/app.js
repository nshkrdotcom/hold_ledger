import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Move within the source pane only; no playback or server-side animation.
const ProofSource = {
  mounted() { this.stage = null; this.reveal() },
  updated() { this.reveal() },
  reveal() {
    if (this.stage === this.el.dataset.stage) return
    this.stage = this.el.dataset.stage
    const line = this.el.querySelector(".active-proof-line")
    if (line) {
      this.el.scrollTop += line.getBoundingClientRect().top - this.el.getBoundingClientRect().top - 12
    }
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {ProofSource},
})
topbar.config({barColors: {0: "#635080"}, shadowColor: "rgba(37,35,48,.2)"})
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())
liveSocket.connect()
window.liveSocket = liveSocket
