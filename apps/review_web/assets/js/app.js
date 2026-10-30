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
const eduDialogTriggers = new WeakSet()
const eduUI = {
  get tooltip() { return document.getElementById("edu-tooltip") },
  get dialog() { return document.getElementById("edu-term-dialog") },
  get drawer() { return document.getElementById("edu-help-drawer") },
  get helpButton() { return document.querySelector("[data-edu-help-open]") },
  get guidance() { return document.querySelector("select[data-edu-guidance]") },
}
let eduActiveTarget = null
let eduDialogTarget = null
let eduLastFocus = null
let eduCloseTimer = null
let eduPreviousDescription = null
let eduRestoringFocus = false

const pageHelp = [
  [/^\/$/, ["Where should I start?", "Follow the 100¢ payment hold, learn to read a claim, or go straight to Case Lab. The page directory links to the rest of the material.", "Catalog counts describe the claims available to read. They do not report a fresh proof run."]],
  [/^\/start/, ["Why keep money on hold after a timeout?", "Follow the four steps. Watch what stays reserved when a reply goes missing, then see why another 100¢ request cannot fit.", "This is a walkthrough of the model, not a transaction with a payment processor."]],
  [/^\/system/, ["Which part of the system does this work?", "Choose a component or hold state to see its role, meaning and source. Follow a request from the pure ledger to the runtime and processor.", "The model describes processor and storage behavior. Real systems need separate evidence for those assumptions."]],
  [/^\/guarantees/, ["What behavior does the policy require?", "Choose a requirement, compare the expected behavior with a mistake, then read the related claims.", "A policy summary helps you find the right claim. The complete statement determines which inputs and outputs it covers."]],
  [/^\/atlas/, ["Which claim covers the behavior I care about?", "Browse the eight families or search for an event, example or claim name. Open a claim to read its promise, a possible mistake and the source behind the explanation.", "The families are a reading order. They do not describe proof dependencies or current checker results."]],
  [/^\/proofs/, ["What does this claim actually promise?", "Follow exact-fit admission from the requirement to requires and expects. Expand the called predicates, then compare the statement with the input you need it to cover.", "Reading a theorem explains its scope. A matching verification report is needed to establish what the checkers accepted."]],
  [/^\/assurance/, ["What does this evidence establish?", "Identify what produced the result, which source it covers and what remains assumed. Use the evidence guide when reading a report in Case Lab.", "A proof of the modeled behavior does not establish physical storage durability or a real processor's compliance."]],
  [/^\/repository/, ["Where can I read the source?", "Choose the question you are investigating and follow its file path or claim link. The map separates policy, implementation, reference behavior and proof support.", "A file location is a starting point. Use the source identity shown in Case Lab when matching code to a report."]],
  [/^\/glossary/, ["What does this term mean here?", "Search for a word, read its example and follow the link back to the relevant page. The same definitions appear in term guides throughout the app.", "A definition explains the term. The source statement supplies its exact conditions."]],
  [/^\/lens/, ["Claim Lens: does the changed claim still cover the policy?", "Read the policy, input and proposed change. Record your judgment, then reveal the explanation. Choose Explore freely if you want to read the worked answer first.", "These are two practice reviews. Hypothetical edits are not checked by Lean, and your answer is a temporary draft."]],
  [/^\/claims|^\/lab/, ["Case Lab: would the claim accept a wrong output?", "Run an input, propose a different output and inspect the conditions. Follow another event or read the source to investigate the result.", "A single-case check covers the selected input and output. Accepting your proposal does not mean the code produces it or that it violates policy."]],
]

function eduTarget(event) {
  const node = event.target instanceof Element ? event.target : null
  return node?.closest("[data-edu-term], [data-edu-hint]") || null
}

function eduExplain(target) {
  const term = eduTerms.get(target.dataset.eduTerm)
  if (term) return term
  if (!target.dataset.eduHint) return null
  return {
    term: (target.getAttribute("aria-label") || target.textContent || "About this control").trim(),
    short: target.dataset.eduHint,
  }
}

function eduCloseTooltip() {
  clearTimeout(eduCloseTimer)
  if (eduActiveTarget) {
    if (eduPreviousDescription) eduActiveTarget.setAttribute("aria-describedby", eduPreviousDescription)
    else eduActiveTarget.removeAttribute("aria-describedby")
  }
  if (eduUI.tooltip) eduUI.tooltip.hidden = true
  eduActiveTarget = null
  eduPreviousDescription = null
}

function eduPositionTooltip(target) {
  const tooltip = eduUI.tooltip
  if (!tooltip || tooltip.hidden || !target?.isConnected) return
  const box = target.getBoundingClientRect()
  const left = Math.max(12, Math.min(innerWidth - tooltip.offsetWidth - 12,
    box.left + box.width / 2 - tooltip.offsetWidth / 2))
  const below = box.bottom + 10
  const top = below + tooltip.offsetHeight < innerHeight - 12
    ? below : Math.max(12, box.top - tooltip.offsetHeight - 10)
  tooltip.style.left = `${left}px`
  tooltip.style.top = `${top}px`
}

function eduShowTooltip(target) {
  if (!eduUI.tooltip || !target?.isConnected || eduDialogTarget || eduRestoringFocus) return
  const explanation = eduExplain(target)
  if (!explanation) return
  clearTimeout(eduCloseTimer)
  if (eduActiveTarget !== target) {
    eduCloseTooltip()
    eduPreviousDescription = target.getAttribute("aria-describedby")
  }
  eduActiveTarget = target
  eduUI.tooltip.querySelector("[data-tooltip-title]").textContent = explanation.term
  eduUI.tooltip.querySelector("[data-tooltip-short]").textContent = explanation.short
  eduUI.tooltip.hidden = false
  target.setAttribute("aria-describedby", [eduPreviousDescription, "edu-tooltip"].filter(Boolean).join(" "))
  eduPositionTooltip(target)
}

function eduCloseTerm(restoreFocus = true) {
  const target = eduDialogTarget
  if (eduUI.dialog) eduUI.dialog.hidden = true
  if (target) target.setAttribute("aria-expanded", "false")
  eduDialogTarget = null
  if (restoreFocus && target?.isConnected) {
    eduRestoringFocus = true
    target.focus({preventScroll: true})
    eduRestoringFocus = false
  }
}

function eduOpenTerm(target) {
  const term = eduTerms.get(target.dataset.eduTerm)
  const dialog = eduUI.dialog
  if (!dialog || !term) return
  eduCloseTooltip()
  eduCloseHelp(false)
  eduCloseTerm(false)
  eduDialogTarget = target
  dialog.querySelector("#edu-term-title").textContent = term.term
  dialog.querySelector("[data-term-meaning]").textContent = term.short
  dialog.querySelector("[data-term-detail]").textContent = term.detail
  dialog.querySelector("[data-term-example]").textContent = term.example
  dialog.querySelector("[data-term-source]").textContent = term.source_path || ""
  dialog.querySelector("[data-term-link]").href = `/glossary#term-${term.id}`
  dialog.querySelector("[data-copy-status]").textContent = ""
  target.setAttribute("aria-expanded", "true")
  target.setAttribute("aria-controls", "edu-term-dialog")
  target.setAttribute("aria-haspopup", "dialog")
  dialog.hidden = false
  dialog.querySelector("[data-edu-term-close]").focus({preventScroll: true})
}

function eduCloseHelp(restoreFocus = true) {
  if (eduUI.drawer) eduUI.drawer.hidden = true
  eduUI.helpButton?.setAttribute("aria-expanded", "false")
  if (restoreFocus && eduLastFocus?.isConnected) eduLastFocus.focus({preventScroll: true})
}

function eduOpenHelp() {
  if (!eduUI.drawer) return
  eduCloseTooltip()
  eduCloseTerm(false)
  eduLastFocus = document.activeElement
  const [title, action, limit] = (pageHelp.find(([re]) => re.test(location.pathname)) || pageHelp[0])[1]
  eduUI.drawer.querySelector("#edu-help-title").textContent = title
  eduUI.drawer.querySelector("#edu-help-description").textContent = action
  eduUI.drawer.querySelector("#edu-help-limit").textContent = limit
  eduUI.drawer.hidden = false
  eduUI.helpButton?.setAttribute("aria-expanded", "true")
  eduUI.drawer.querySelector("[data-edu-help-close]")?.focus({preventScroll: true})
}

async function eduCopy(text, status) {
  if (!status) return
  try {
    await navigator.clipboard.writeText(text)
    status.textContent = "Copied."
  } catch {
    status.textContent = "Copy is unavailable in this browser. Select the text to copy it."
  }
}

function eduMarkNav() {
  for (const a of document.querySelectorAll("[data-global-nav] [data-nav]")) {
    const segment = a.dataset.nav
    const active = segment === "/" ? location.pathname === "/"
      : segment === "/lab" ? /^\/(lab|claims)(\/|$)/.test(location.pathname)
      : location.pathname === segment || location.pathname.startsWith(`${segment}/`)
    if (active) a.setAttribute("aria-current", "page")
    else a.removeAttribute("aria-current")
  }
  document.querySelectorAll("[data-edu-term]").forEach(eduSyncTerm)
}

function eduSyncTerm(target) {
  if (!(target instanceof Element)) return
  if (target === eduUI.helpButton) {
    const expanded = String(Boolean(eduUI.drawer && !eduUI.drawer.hidden))
    if (target.getAttribute("aria-expanded") !== expanded) {
      target.setAttribute("aria-expanded", expanded)
    }
    return
  }
  const attributes = {
    "aria-haspopup": "dialog",
    "aria-controls": "edu-term-dialog",
    "aria-expanded": String(target === eduDialogTarget),
  }
  const opensDialog = eduTerms.has(target.dataset.eduTerm) &&
    !target.matches("a, input, select, textarea, [phx-click]")
  if (!opensDialog) {
    if (eduDialogTriggers.has(target)) {
      Object.keys(attributes).forEach(name => target.removeAttribute(name))
      eduDialogTriggers.delete(target)
    }
    return
  }
  eduDialogTriggers.add(target)
  for (const [name, value] of Object.entries(attributes)) {
    if (target.getAttribute(name) !== value) target.setAttribute(name, value)
  }
}

function eduRestoreGuidance() {
  let density = document.documentElement.dataset.eduGuidance || "guided"
  try { density = localStorage.getItem("hold_ledger_education_density") || density } catch { /* optional preference */ }
  if (!["guided", "focused"].includes(density)) density = "guided"
  document.documentElement.dataset.eduGuidance = density
  if (eduUI.guidance) eduUI.guidance.value = density
}

eduRestoreGuidance()
document.addEventListener("change", event => {
  if (!event.target.matches("select[data-edu-guidance]")) return
  const density = event.target.value
  document.documentElement.dataset.eduGuidance = density
  try { localStorage.setItem("hold_ledger_education_density", density) } catch { /* optional preference */ }
})
document.addEventListener("pointerover", event => {
  if (eduUI.tooltip?.contains(event.target)) clearTimeout(eduCloseTimer)
  if (event.pointerType !== "touch") {
    const target = eduTarget(event)
    if (target && !target.contains(event.relatedTarget)) eduShowTooltip(target)
  }
})
document.addEventListener("pointerout", event => {
  if (!eduActiveTarget || eduActiveTarget.contains(document.activeElement)) return
  const fromHelp = eduActiveTarget.contains(event.target) || eduUI.tooltip?.contains(event.target)
  const toHelp = eduActiveTarget.contains(event.relatedTarget) || eduUI.tooltip?.contains(event.relatedTarget)
  if (fromHelp && !toHelp) eduCloseTimer = setTimeout(eduCloseTooltip, 150)
})
document.addEventListener("focusin", event => {
  const target = eduTarget(event)
  if (target) eduShowTooltip(target)
})
document.addEventListener("focusout", event => {
  if (eduActiveTarget?.contains(event.target)) eduCloseTooltip()
})
document.addEventListener("click", event => {
  const node = event.target instanceof Element ? event.target : null
  if (!node) return
  if (node.closest("[data-edu-help-open]")) {
    if (eduUI.drawer?.hidden) eduOpenHelp()
    else eduCloseHelp()
    return
  }
  if (node.closest("[data-edu-help-close]")) { eduCloseHelp(); return }
  if (node.closest("[data-edu-term-close]")) { eduCloseTerm(); return }
  if (node.closest("[data-copy-explanation]") && eduDialogTarget) {
    const term = eduTerms.get(eduDialogTarget.dataset.eduTerm)
    eduCopy([term.term, term.short, term.detail, term.example, term.source_path].filter(Boolean).join("\n\n"),
      eduUI.dialog.querySelector("[data-copy-status]"))
    return
  }
  const copy = node.closest("[data-copy-text]")
  if (copy) { eduCopy(copy.dataset.copyText, document.getElementById("copy-status")); return }
  // A hint on an ordinary control explains it but never replaces its action.
  const term = node.closest("[data-edu-term]")
  if (term && !term.matches("a, input, select, textarea, [phx-click]")) {
    event.preventDefault()
    if (eduDialogTarget === term) eduCloseTerm()
    else eduOpenTerm(term)
    return
  }
  if (!eduUI.dialog?.contains(node)) eduCloseTerm(false)
  if (!eduUI.drawer?.contains(node)) eduCloseHelp(false)
  eduCloseTooltip()
})
document.addEventListener("keydown", event => {
  if (event.key === "Escape") {
    const open = eduDialogTarget || (eduUI.drawer && !eduUI.drawer.hidden) || eduActiveTarget
    if (open) {
      event.preventDefault()
      event.stopPropagation()
      eduCloseTooltip()
      if (eduDialogTarget) eduCloseTerm()
      else if (eduUI.drawer && !eduUI.drawer.hidden) eduCloseHelp()
    }
    const reference = document.getElementById("reference-nav")
    if (reference?.open && reference.contains(event.target)) {
      reference.open = false
      reference.querySelector("summary").focus()
    }
  }
  if ((event.key === "Enter" || event.key === " ") &&
      event.target?.matches?.("[data-edu-term]:not(button):not(a):not(input):not(select):not(textarea):not([phx-click])")) {
    event.preventDefault()
    if (eduDialogTarget === event.target) eduCloseTerm()
    else eduOpenTerm(event.target)
  }
}, true)
window.addEventListener("scroll", () => {
  if (eduActiveTarget?.contains(document.activeElement)) eduPositionTooltip(eduActiveTarget)
  else eduCloseTooltip()
}, {capture: true, passive: true})
window.addEventListener("resize", () => {
  if (eduActiveTarget) eduPositionTooltip(eduActiveTarget)
})
window.addEventListener("phx:page-loading-stop", () => {
  eduCloseTooltip()
  eduCloseTerm(false)
  eduCloseHelp(false)
  eduMarkNav()
  eduRestoreGuidance()
})
new MutationObserver(records => {
  const affectsExplanation = record => record.type !== "attributes" ||
    (["data-edu-term", "data-edu-hint", "phx-click"].includes(record.attributeName) &&
      record.oldValue !== record.target.getAttribute(record.attributeName))
  const changed = target => target && (!target.isConnected ||
    records.some(record => target.contains(record.target) && affectsExplanation(record)))
  if (changed(eduActiveTarget)) eduCloseTooltip()
  if (changed(eduDialogTarget)) eduCloseTerm(false)
  for (const record of records) {
    if (record.type === "attributes") eduSyncTerm(record.target)
  }
  if (records.some(record => record.type === "childList")) {
    document.querySelectorAll("[data-edu-term]").forEach(eduSyncTerm)
    eduSyncTerm(eduUI.helpButton)
  }
}).observe(document.body, {
  childList: true,
  characterData: true,
  subtree: true,
  attributes: true,
  attributeOldValue: true,
  attributeFilter: ["data-edu-term", "data-edu-hint", "phx-click", "aria-haspopup", "aria-controls", "aria-expanded"],
})
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
