import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import educationGlossary from "../../priv/education_glossary.json"

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

const InlineAlternative = {
  mounted() {
    this.keydown = event => {
      if (event.key !== "Escape") return
      event.preventDefault()
      this.pushEvent("close_tools", {}, () => {
        document.getElementById("edit-candidate")?.focus({preventScroll: true})
      })
    }
    this.el.addEventListener("keydown", this.keydown)
  },
  destroyed() {
    this.el.removeEventListener("keydown", this.keydown)
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

// A transient clipboard aid for the author's own pre-reveal answer. It does
// not persist, submit, score, or imply any verification status.
const CopyReview = {
  mounted() {
    this.copy = async () => {
      const message = document.getElementById("lens-copy-status")
      try {
        await navigator.clipboard.writeText(this.el.dataset.packet || "")
        if (message) message.textContent = "Local argument copied"
      } catch {
        if (message) message.textContent = "Clipboard unavailable; select your answer to copy"
      }
    }
    this.el.addEventListener("click", this.copy)
  },
  destroyed() {
    this.el.removeEventListener("click", this.copy)
  },
}

// Educational assistance is deliberately a single delegated listener. Both
// workbenches are re-rendered by LiveView; no per-node hook needs to survive a
// patch. The glossary is the same source as /glossary (not a parallel judge).
const eduTerms = new Map(educationGlossary.terms.map(term => [term.id, term]))
const eduTooltip = document.getElementById("edu-tooltip")
const tooltipTitle = eduTooltip?.querySelector("[data-tooltip-title]")
const tooltipShort = eduTooltip?.querySelector("[data-tooltip-short]")
const tooltipDetail = eduTooltip?.querySelector("[data-tooltip-detail]")
const tooltipLink = eduTooltip?.querySelector("[data-tooltip-link]")
const eduHelpDrawer = document.getElementById("edu-help-drawer")
const eduHelpButton = document.querySelector("[data-edu-help-open]")
let eduActiveTarget = null
let eduPinned = false
let eduLastFocus = null

const eduWords = [
  ["precondition", "requires"], ["requires", "requires"], ["postcondition", "expects"],
  ["expects", "expects"], ["pointwise", "pointwise"], ["hypothetical", "hypothetical"],
  ["proof status", "proof-status"], ["formal acceptance", "proof-status"],
  ["source", "source-identity"], ["checker", "proof-status"],
  ["proof", "theorem"], ["policy", "specification"], ["argument", "review"],
  ["condition", "requires"], ["applicability", "coverage"],
  ["evidence", "proof-status"], ["assumption", "assumption"],
  ["voiding", "voiding"], ["voided", "voided"], ["void", "effect-intent"],
  ["terminal", "terminal-fence"], ["processor", "processor"],
  ["unknown", "unknown"], ["timeout", "timeout"], ["reserved", "reserved"],
  ["capacity", "capacity"], ["recalculate", "capacity"],
  ["amount", "capacity"], ["slot", "capacity"], ["result", "pointwise"],
  ["effect", "effect"], ["output", "pointwise"],
  ["witness", "witness"], ["alternative", "hypothetical"],
  ["candidate", "hypothetical"], ["contrast", "counterexample"],
  ["trace", "witness"], ["timeline", "event"], ["event", "event"],
  ["law", "law"], ["claim", "claim"], ["retry", "idempotency"],
  ["replay", "replay"], ["journal", "journal"],
  ["review", "review"], ["compare", "source-identity"],
  ["note", "review"], ["snapshot", "source-identity"],
  ["export", "source-identity"], ["induction", "induction"],
]

const pageHelp = [
  [/^\/$|^\/start/, ["From payment risk to a formal claim", "Start with the missing-reply scenario. A hold reserves capacity while the remote authorization may still be live. Follow the linked system, requirements, proof and evidence screens at your own pace."]],
  [/^\/system/, ["Meet the code and its trust boundaries", "The Ledger computes pure state transitions. The independent Spec describes intended behavior. Runtime sends effects, and the processor sits beyond the formal model. Select a layer or status to see its meaning."]],
  [/^\/guarantees/, ["Read policy before proofs", "These six human themes summarize the governing specification. Select a guarantee, compare safe and unsafe near-misses, then open the registered law group. The themes are not themselves proof receipts."]],
  [/^\/atlas/, ["Every registered claim has a place", "Use the eight editorial families or search across the source catalog. A group is registered, not necessarily freshly checked. Select a profile for its exact slug and source; separate conceptual grouping from proof dependency."]],
  [/^\/proofs/, ["Read the verification pipeline", "Five different layers: human policy, Elixir code and law, Lynx translation, Lean statement and checked evidence. A proof can be valid for a claim that omits desired behavior."]],
  [/^\/assurance/, ["Do not confuse evidence levels", "An illustrative example, pointwise check, proof source, focused elaboration and source-matched formal receipt have different meanings. The real processor and journal introduce separate assumptions."]],
  [/^\/repository/, ["Find files by their purpose", "This source map shows the pure Ledger, independent Spec, runtime, laws, Lean support, proof registry and review companion. Use the claim profiles for source-bound technical review."]],
  [/^\/glossary/, ["Look up a concept when it appears", "Search the terms or follow their example links back into the project. Tooltips in the workbench use these same definitions and can be opened with keyboard focus or touch."]],
  [/^\/lens/, ["Claim Lens: test whether a claim expresses policy", "Start with the governing requirement and a concrete witness. Commit your own classification before revealing the pointwise verdict. Hypothetical edits have NOT been Lean checked. Only two guided claims are configured."]],
  [/^\/claims|^\/lab/, ["Case Lab: what does this law check here?", "Choose a registered law and experiment with a concrete event and an alternative output. The pointwise check is not a universal theorem. Open source and proof readings for provenance; external processor behavior is still assumed."]],
]

function eduCloseTooltip() {
  if (!eduTooltip) return
  if (eduActiveTarget) eduActiveTarget.removeAttribute("aria-describedby")
  eduTooltip.hidden = true
  eduTooltip.dataset.pinned = "false"
  eduActiveTarget = null
  eduPinned = false
}
function eduTarget(event) {
  const node = event.target instanceof Element ? event.target : null
  if (!node) return null
  const explicit = node.closest("[data-edu-term], [data-edu-hint]")
  if (explicit) return explicit
  if (!node.closest("#review-document, #claim-lens, .site-tools")) return null
  return node.closest("button, summary, label, select, input, textarea, a, dt, th, [data-kind], .status-pill, .field-delta, .lens-step, .lens-evidence, [role='tab'], [role='button']")
}
function eduExplain(target) {
  const id = target.dataset.eduTerm
  const term = id && eduTerms.get(id)
  if (term) return {term: term.term, short: term.short, detail: term.detail, link: `/glossary#term-${term.id}`}
  const hint = target.dataset.eduHint
  const label = (target.getAttribute("aria-label") || target.innerText || target.value || target.getAttribute("placeholder") || target.getAttribute("title") || "Review control").trim().replace(/\s+/g, " ").slice(0, 110)
  const text = label.toLowerCase()
  const matched = eduWords.find(([keyword]) => text.includes(keyword))
  const concept = matched && eduTerms.get(matched[1])
  if (hint) return {term: label || "Explanation", short: hint, detail: concept?.detail || "Use the page guide for the relationship between this control and the evidence it displays.", link: concept ? `/glossary#term-${concept.id}` : "/glossary"}
  if (concept) return {term: label || concept.term, short: concept.short, detail: concept.detail, link: `/glossary#term-${concept.id}`}
  return {term: label || "Review control", short: "An interaction in the review workbench. Its result is bounded by the selected source, case and evidence.", detail: "Case Lab and Claim Lens show model cases and reviewed source. A screen interaction is not itself a new formal checker receipt.", link: "/assurance"}
}
function eduShowTooltip(target, pinned = false) {
  if (!eduTooltip || !target?.isConnected) return
  if (eduPinned && !pinned && target !== eduActiveTarget) return
  if (eduActiveTarget && eduActiveTarget !== target) eduActiveTarget.removeAttribute("aria-describedby")
  const explanation = eduExplain(target)
  tooltipTitle.textContent = explanation.term
  tooltipShort.textContent = explanation.short
  tooltipDetail.textContent = explanation.detail
  tooltipLink.setAttribute("href", explanation.link)
  eduTooltip.hidden = false
  eduTooltip.dataset.pinned = String(pinned)
  eduPinned = pinned
  eduActiveTarget = target
  target.setAttribute("aria-describedby", "edu-tooltip")
  const box = target.getBoundingClientRect()
  const width = eduTooltip.offsetWidth
  const height = eduTooltip.offsetHeight
  const left = Math.max(10, Math.min(window.innerWidth - width - 10, box.left + box.width / 2 - width / 2))
  const below = box.bottom + 10
  const top = below + height < window.innerHeight - 10 ? below : Math.max(10, box.top - height - 10)
  eduTooltip.style.left = `${left}px`
  eduTooltip.style.top = `${top}px`
}

function eduCloseHelp() {
  if (!eduHelpDrawer) return
  eduHelpDrawer.hidden = true
  eduHelpButton?.setAttribute("aria-expanded", "false")
  if (eduLastFocus?.isConnected) eduLastFocus.focus({preventScroll: true})
}
function eduOpenHelp() {
  if (!eduHelpDrawer) return
  eduCloseTooltip()
  eduLastFocus = document.activeElement
  const [title, detail] = (pageHelp.find(([re]) => re.test(location.pathname)) || pageHelp[0])[1]
  eduHelpDrawer.querySelector("#edu-help-title").textContent = title
  eduHelpDrawer.querySelector("#edu-help-description").textContent = detail
  eduHelpDrawer.hidden = false
  eduHelpButton?.setAttribute("aria-expanded", "true")
  eduHelpDrawer.querySelector("[data-edu-help-close]")?.focus({preventScroll: true})
}
function eduMarkNav() {
  for (const a of document.querySelectorAll("[data-global-nav] [data-nav]")) {
    const segment = a.dataset.nav
    const active = segment === "/" ? location.pathname === "/" : location.pathname.startsWith(segment)
    if (active) a.setAttribute("aria-current", "page")
    else a.removeAttribute("aria-current")
  }
}
const guidanceSelect = document.querySelector("[data-edu-guidance]")
try {
  const stored = localStorage.getItem("hold_ledger_education_density")
  if (stored === "guided" || stored === "focused") guidanceSelect.value = stored
} catch { /* Browser storage is optional */ }
document.documentElement.dataset.eduGuidance = guidanceSelect?.value || "guided"
guidanceSelect?.addEventListener("change", () => {
  document.documentElement.dataset.eduGuidance = guidanceSelect.value
  try { localStorage.setItem("hold_ledger_education_density", guidanceSelect.value) } catch { /* optional */ }
})
document.addEventListener("pointerover", event => {
  if (event.pointerType === "touch") return
  const target = eduTarget(event)
  if (target && (!eduPinned || target === eduActiveTarget)) eduShowTooltip(target)
})
document.addEventListener("pointerout", event => {
  if (!eduPinned && eduActiveTarget && eduActiveTarget.contains(event.target) &&
      !eduActiveTarget.contains(event.relatedTarget)) eduCloseTooltip()
})
document.addEventListener("focusin", event => {
  const target = eduTarget(event)
  if (target && !eduPinned) eduShowTooltip(target)
})
document.addEventListener("focusout", event => {
  if (!eduPinned && eduActiveTarget?.contains(event.target)) eduCloseTooltip()
})
document.addEventListener("click", event => {
  const node = event.target instanceof Element ? event.target : null
  if (!node) return
  if (node.closest("[data-edu-help-open]")) {
    event.preventDefault()
    if (eduHelpDrawer?.hidden) eduOpenHelp()
    else eduCloseHelp()
    return
  }
  if (node.closest("[data-edu-help-close]")) {eduCloseHelp(); return}
  if (!eduHelpDrawer?.hidden && !eduHelpDrawer.contains(node) && !node.closest("[data-edu-help-open]")) eduCloseHelp()
  const term = node.closest("[data-edu-term]")
  if (term) {
    event.preventDefault()
    if (eduPinned && eduActiveTarget === term) eduCloseTooltip()
    else eduShowTooltip(term, true)
  } else if (eduPinned && !eduTooltip?.contains(node)) eduCloseTooltip()
})
document.addEventListener("keydown", event => {
  if (event.key === "Escape") {
    if (eduPinned || !eduTooltip?.hidden) eduCloseTooltip()
    if (!eduHelpDrawer?.hidden) eduCloseHelp()
  }
  if ((event.key === "Enter" || event.key === " ") && event.target?.matches?.("[data-edu-term]")) {
    event.preventDefault()
    eduShowTooltip(event.target, true)
  }
})
window.addEventListener("scroll", () => { if (!eduPinned) eduCloseTooltip() }, {capture:true, passive:true})
window.addEventListener("phx:page-loading-stop", () => { eduCloseTooltip(); eduMarkNav() })
window.addEventListener("popstate", eduMarkNav)
eduMarkNav()

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {InlineTools, InlineAlternative, QuestionPanel, CopyReview},
})
topbar.config({barColors: {0: "#635080"}, shadowColor: "rgba(37,35,48,.2)"})
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())
liveSocket.connect()
window.liveSocket = liveSocket
