import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import educationGlossary from "../../priv/education_glossary.json"
import educationHelp from "../../priv/education_help.json"

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
const eduControls = new Map(Object.entries(educationHelp.controls || {}))
const eduRegisteredTargets = new WeakMap()
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

function eduPageHelp() {
  const path = location.pathname
  const page = educationHelp.pages.find(item => path === item.path ||
    (item.path !== "/" && path.startsWith(`${item.path}/`))) || educationHelp.pages[0]
  if (path.startsWith("/lens") && new URLSearchParams(location.search).get("mode") === "explore") {
    return {...page, detail: "The worked explanation is visible while you try the example. Compare the policy, proposed claim change and input; switch to Review first to make your judgment before seeing feedback."}
  }
  if (/^\/(claims|lab)(\/|$)/.test(path) &&
      document.getElementById("review-document")?.dataset.caseView === "inspector") {
    return {...page, detail: "Inspector opens the conditions and proof source. Follow the observed values into the statement, or return to Guided for the case's main reading order. Your case and unsaved edits stay the same."}
  }
  return page
}

// Selectors name authored controls; the client never guesses definitions from
// their label text. Keep the registry separate from the glossary's concepts.
function eduSyncControls() {
  for (const target of document.querySelectorAll("[data-help]")) {
    const assigned = eduRegisteredTargets.get(target)
    if (assigned && !target.matches(eduControls.get(assigned)?.selector || ":not(*)")) {
      target.removeAttribute("data-help")
      eduRegisteredTargets.delete(target)
    }
  }
  for (const [key, entry] of eduControls) {
    for (const target of document.querySelectorAll(entry.selector)) {
      if (target.closest("#edu-help-drawer, #edu-term-dialog, #edu-tooltip")) continue
      if (!target.dataset.help) {
        target.dataset.help = key
        eduRegisteredTargets.set(target, key)
      }
    }
  }
}

function eduVisible(target) {
  return target.isConnected && !target.closest("[hidden], [aria-hidden='true']") &&
    target.getClientRects().length > 0
}

function eduControlGuide() {
  const list = document.getElementById("edu-control-help")
  if (!list) return
  list.replaceChildren()
  const shown = new Set()
  for (const target of document.querySelectorAll("[data-help]")) {
    const key = target.dataset.help
    const entry = eduControls.get(key)
    if (!entry || shown.has(key) || !eduVisible(target)) continue
    shown.add(key)
    const button = document.createElement("button")
    button.type = "button"
    button.dataset.helpControl = key
    button.textContent = entry.term
    button.setAttribute("aria-haspopup", "dialog")
    button.setAttribute("aria-controls", "edu-term-dialog")
    list.append(button)
  }
  if (!shown.size) {
    const note = document.createElement("p")
    note.textContent = "The controls on this page use their visible labels. Look up unfamiliar terms in the glossary."
    list.append(note)
  }
}

function eduTarget(event) {
  const node = event.target instanceof Element ? event.target : null
  return node?.closest("[data-edu-term], [data-edu-hint], [data-help]") || null
}

function eduExplain(target) {
  const control = eduControls.get(target.dataset.help)
  if (control) return {...control, id: target.dataset.help, kind: "control"}
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

function eduRestoreFocus(target) {
  eduRestoringFocus = true
  if (target?.isConnected && eduVisible(target) && !target.matches(":disabled")) {
    target.focus({preventScroll: true})
  }
  if (document.activeElement !== target) eduUI.helpButton?.focus({preventScroll: true})
  eduRestoringFocus = false
}

function eduCloseTerm(restoreFocus = true) {
  const target = eduDialogTarget
  if (eduUI.dialog) eduUI.dialog.hidden = true
  if (target && eduDialogTriggers.has(target)) target.setAttribute("aria-expanded", "false")
  eduDialogTarget = null
  if (restoreFocus) eduRestoreFocus(target)
}

function eduOptionalText(dialog, selector, text, sectionSelector) {
  const node = dialog.querySelector(selector)
  if (!node) return
  node.textContent = text || ""
  const section = sectionSelector ? dialog.querySelector(sectionSelector) : node
  if (section) section.hidden = !text
}

function eduPositionDialog(target) {
  const dialog = eduUI.dialog
  if (!dialog || dialog.hidden) return
  if (innerWidth <= 650) {
    dialog.style.top = ""
    dialog.style.left = ""
    return
  }
  const box = target.getBoundingClientRect()
  const left = Math.max(12, Math.min(innerWidth - dialog.offsetWidth - 12, box.left))
  const top = Math.max(12, Math.min(innerHeight - dialog.offsetHeight - 12, box.bottom + 8))
  dialog.style.left = `${left}px`
  dialog.style.top = `${top}px`
}

function eduOpenTerm(target) {
  const term = eduExplain(target)
  const dialog = eduUI.dialog
  if (!dialog || !term) return
  eduCloseTooltip()
  eduCloseHelp(false)
  eduCloseTerm(false)
  eduDialogTarget = target
  dialog.querySelector("#edu-term-title").textContent = term.term
  dialog.querySelector("[data-term-meaning]").textContent = term.short
  eduOptionalText(dialog, "[data-term-detail]", term.detail)
  eduOptionalText(dialog, "[data-term-example]", term.example, "[data-term-example-section]")
  eduOptionalText(dialog, "[data-term-why]", term.why_it_matters, "[data-term-why-section]")
  eduOptionalText(dialog, "[data-term-limit]", term.limit, "[data-term-limit-section]")
  eduOptionalText(dialog, "[data-term-source]", term.source_path)
  const link = dialog.querySelector("[data-term-link]")
  link.href = term.kind === "control" ? term.link || "/glossary" : `/glossary#term-${term.id}`
  link.textContent = term.kind === "control" ? "Read the related guide →" : "Read the glossary entry →"
  const lookups = dialog.querySelector("[data-term-lookups]")
  if (lookups) {
    lookups.replaceChildren()
    for (const item of term.lookup || []) {
      if (!/^https:\/\//.test(item.url)) continue
      const reference = document.createElement("a")
      reference.href = item.url
      reference.textContent = item.label
      lookups.append(reference)
    }
  }
  dialog.querySelector("[data-copy-status]").textContent = ""
  if (eduDialogTriggers.has(target)) target.setAttribute("aria-expanded", "true")
  dialog.hidden = false
  eduPositionDialog(target)
  dialog.querySelector("[data-edu-term-close]").focus({preventScroll: true})
}

function eduCloseHelp(restoreFocus = true) {
  if (eduUI.drawer) eduUI.drawer.hidden = true
  eduUI.helpButton?.setAttribute("aria-expanded", "false")
  if (restoreFocus) eduRestoreFocus(eduLastFocus)
}

function eduOpenHelp() {
  if (!eduUI.drawer) return
  eduCloseTooltip()
  eduCloseTerm(false)
  eduLastFocus = document.activeElement
  const page = eduPageHelp()
  eduUI.drawer.querySelector("#edu-help-title").textContent = page.title
  eduUI.drawer.querySelector("#edu-help-description").textContent = page.detail
  eduUI.drawer.querySelector("#edu-help-limit").textContent = page.limit
  eduSyncControls()
  eduControlGuide()
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
  for (const a of document.querySelectorAll("#global-header [data-nav]")) {
    const segment = a.dataset.nav
    const active = segment === "/" ? location.pathname === "/"
      : segment === "/lab" ? /^\/(lab|claims)(\/|$)/.test(location.pathname)
      : location.pathname === segment || location.pathname.startsWith(`${segment}/`)
    if (active) a.setAttribute("aria-current", "page")
    else a.removeAttribute("aria-current")
  }
  document.querySelectorAll("[data-edu-term]").forEach(eduSyncTerm)
  eduSyncControls()
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
  const controlHelp = node.closest("[data-help-control]")
  if (controlHelp) {
    const key = controlHelp.dataset.helpControl
    const target = [...document.querySelectorAll("[data-help]")].find(item =>
      item.dataset.help === key && eduVisible(item))
    if (target) eduOpenTerm(target)
    return
  }
  if (node.closest("[data-edu-help-close]")) { eduCloseHelp(); return }
  if (node.closest("[data-edu-term-close]")) { eduCloseTerm(); return }
  if (node.closest("[data-copy-explanation]") && eduDialogTarget) {
    const term = eduExplain(eduDialogTarget)
    eduCopy([term.term, term.short, term.detail, term.why_it_matters, term.limit, term.example, term.source_path].filter(Boolean).join("\n\n"),
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
  const editing = event.target instanceof Element && event.target.closest("input, textarea, select, [contenteditable='true']")
  if (event.key === "?" && !editing && !event.ctrlKey && !event.metaKey && !event.altKey) {
    event.preventDefault()
    if (eduUI.drawer?.hidden) eduOpenHelp()
    else eduCloseHelp()
    return
  }
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
  if (eduDialogTarget) eduPositionDialog(eduDialogTarget)
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
    (["data-edu-term", "data-edu-hint", "data-help", "phx-click"].includes(record.attributeName) &&
      record.oldValue !== record.target.getAttribute(record.attributeName))
  const changed = target => target && (!target.isConnected ||
    records.some(record => target.contains(record.target) && affectsExplanation(record)))
  if (changed(eduActiveTarget)) eduCloseTooltip()
  if (changed(eduDialogTarget)) eduCloseTerm(false)
  for (const record of records) {
    if (record.type === "attributes") eduSyncTerm(record.target)
  }
  if (records.some(record => record.type === "attributes" &&
      ["phx-click", "phx-value-tool", "phx-value-view", "id"].includes(record.attributeName))) {
    eduSyncControls()
  }
  if (records.some(record => record.type === "childList")) {
    document.querySelectorAll("[data-edu-term]").forEach(eduSyncTerm)
    eduSyncTerm(eduUI.helpButton)
    eduSyncControls()
  }
}).observe(document.body, {
  childList: true,
  characterData: true,
  subtree: true,
  attributes: true,
  attributeOldValue: true,
  attributeFilter: ["data-edu-term", "data-edu-hint", "data-help", "phx-click", "phx-value-tool", "phx-value-view", "id", "aria-haspopup", "aria-controls", "aria-expanded"],
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
