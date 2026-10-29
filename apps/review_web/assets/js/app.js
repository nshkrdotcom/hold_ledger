import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

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
    for (const id of detail.open_ids || []) {
      const disclosure = document.getElementById(id)
      if (disclosure?.tagName === "DETAILS") disclosure.open = true
    }
    for (let ancestor = panel.parentElement; ancestor; ancestor = ancestor.parentElement) {
      if (ancestor.tagName === "DETAILS") ancestor.open = true
    }
    panel.scrollIntoView({block: "start"})
    const target = panel.matches(".logic-node")
      ? panel.querySelector(":scope > .logic-line > .clause-select") || panel
      : panel
    if (target === panel) target.setAttribute("tabindex", "-1")
    target.focus({preventScroll: true})
  })
})

const QuestionPanel = {
  mounted() {
    this.previousPanel = null
    this.restore = true
    this.position = () => {
      const panel = this.el.querySelector('#question-panel')
      if (!panel) return
      const viewport = window.visualViewport
      const top = Math.max(8, document.querySelector('.site-header').getBoundingClientRect().bottom + 8)
      panel.style.top = `${top}px`
      panel.style.maxHeight = `${Math.max(0, (viewport?.height || innerHeight) - top - 12)}px`
    }
    this.outside = event => {
      if (this.el.querySelector('#question-panel') && !this.el.contains(event.target)) {
        this.restore = false
        this.pushEventTo(Number(this.el.dataset.target), 'close', {})
      }
    }
    this.keydown = event => {
      const panel = this.el.querySelector('#question-panel')
      if (event.key === 'Escape' && panel?.contains(event.target)) {
        event.preventDefault()
        event.stopPropagation()
        this.restore = true
        this.pushEventTo(Number(this.el.dataset.target), 'close', {})
      }
    }
    this.copy = async event => {
      const button = event.target.closest('[data-copy-answer]')
      if (!button) return
      try {
        await navigator.clipboard.writeText(button.dataset.copyAnswer)
        button.textContent = 'Copied'
      } catch { button.textContent = 'Copy unavailable; use export' }
    }
    document.addEventListener('pointerdown', this.outside)
    this.el.addEventListener('keydown', this.keydown)
    this.el.addEventListener('click', this.copy)
    window.addEventListener('resize', this.position)
    window.visualViewport?.addEventListener('resize', this.position)
  },
  updated() {
    const panel = this.el.querySelector('#question-panel')
    if (panel && !this.previousPanel) {
      this.opener = document.activeElement
      this.restore = true
      ;(panel.querySelector('textarea') || panel).focus({preventScroll: true})
    } else if (!panel && this.previousPanel && this.restore) {
      const target = this.opener?.isConnected && this.el.contains(this.opener)
        ? this.opener
        : this.el.querySelector('.question-preview, #question-history')
      target?.focus({preventScroll: true})
    }
    this.previousPanel = panel
    this.position()
  },
  destroyed() {
    document.removeEventListener('pointerdown', this.outside)
    this.el.removeEventListener('keydown', this.keydown)
    this.el.removeEventListener('click', this.copy)
    window.removeEventListener('resize', this.position)
    window.visualViewport?.removeEventListener('resize', this.position)
  },
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {InlineTools, QuestionPanel},
})
topbar.config({barColors: {0: "#635080"}, shadowColor: "rgba(37,35,48,.2)"})
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())
liveSocket.connect()
window.liveSocket = liveSocket
