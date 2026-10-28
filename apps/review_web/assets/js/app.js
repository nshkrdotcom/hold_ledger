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

const ToolDrawer = {
  mounted() {
    this.opener = document.activeElement
    this.background = document.getElementById("review-document")
    this.background.inert = true
    this.previousOverflow = document.body.style.overflow
    document.body.style.overflow = "hidden"
    this.el.querySelector("#close-tools").focus()
    this.keydown = event => {
      if (event.key === "Escape") {
        event.preventDefault()
        this.pushEvent("close_tools", {})
      }
      if (event.key !== "Tab") return
      const controls = [...this.el.querySelectorAll("button, input, select, textarea, a[href]")]
        .filter(node => !node.disabled && node.getClientRects().length)
      const first = controls[0], last = controls[controls.length - 1]
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault(); last?.focus()
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault(); first?.focus()
      }
    }
    this.el.addEventListener("keydown", this.keydown)
  },
  destroyed() {
    this.el.removeEventListener("keydown", this.keydown)
    this.background.inert = false
    document.body.style.overflow = this.previousOverflow
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
  hooks: {ProofSource, ToolDrawer},
})
topbar.config({barColors: {0: "#635080"}, shadowColor: "rgba(37,35,48,.2)"})
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())
liveSocket.connect()
window.liveSocket = liveSocket
