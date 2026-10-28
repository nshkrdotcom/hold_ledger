export const VisualLab = {
  mounted() {
    this.player = null
    this.timer = null
    this.pinned = null
    this.motion = window.matchMedia('(prefers-reduced-motion: reduce)')
    this.onClick = event => {
      const play = event.target.closest('[data-play]')
      const step = event.target.closest('[data-step]')
      const cue = event.target.closest('[data-link-cue]')
      if (play) {
        const name = play.dataset.play
        const wasPlaying = this.player === name
        this.stop()
        if (!wasPlaying && !this.motion.matches) {
          this.player = name
          this.paintPlayback()
          this.tick()
        }
      } else if (step) {
        this.stop()
        const [name, direction] = step.dataset.step.split(':')
        this.advance(name, Number(direction))
      } else if (cue) {
        this.pinned = this.pinned === cue.dataset.linkCue ? null : cue.dataset.linkCue
        this.highlight(this.pinned)
      } else {
        this.stop()
      }
      if (event.target.closest('[data-open-inspector]')) {
        document.querySelector('#technical-inspector').open = true
        this.pushEvent('open_inspector', {})
      }
    }
    this.onHover = event => {
      const cue = event.target.closest('[data-link-cue]')
      this.highlight(cue ? cue.dataset.linkCue : this.pinned)
    }
    this.onLeave = () => this.highlight(this.pinned)
    this.onInput = () => this.stop()
    this.onVisibility = () => { if (document.hidden) this.stop() }
    this.el.addEventListener('click', this.onClick)
    this.el.addEventListener('pointerover', this.onHover)
    this.el.addEventListener('focusin', this.onHover)
    this.el.addEventListener('pointerleave', this.onLeave)
    this.el.addEventListener('focusout', this.onLeave)
    this.el.addEventListener('input', this.onInput)
    document.addEventListener('visibilitychange', this.onVisibility)
    this.motion.addEventListener('change', this.onInput)
    this.openInspector = event => {
      if (!this.el.contains(event.target)) this.stop()
      if (event.target.closest('[data-open-inspector], a[href="#technical-inspector"]')) {
        document.querySelector('#technical-inspector').open = true
        this.pushEvent('open_inspector', {})
      }
    }
    document.addEventListener('click', this.openInspector)
    window.addEventListener('phx:page-loading-start', this.onInput)
    this.paintPlayback()
  },
  updated() {
    this.highlight(this.pinned)
    this.paintPlayback()
  },
  destroyed() {
    this.stop()
    document.removeEventListener('visibilitychange', this.onVisibility)
    document.removeEventListener('click', this.openInspector)
    window.removeEventListener('phx:page-loading-start', this.onInput)
    this.motion.removeEventListener('change', this.onInput)
  },
  highlight(cue) {
    const names = (cue || '').split(' ')
    this.el.querySelectorAll('[data-link-target]').forEach(el => {
      el.classList.toggle('linked-value', el.dataset.linkTarget.split(' ').some(name => names.includes(name)))
    })
    this.el.querySelectorAll('[data-link-cue]').forEach(el => {
      el.setAttribute('aria-pressed', String(Boolean(this.pinned) && el.dataset.linkCue === this.pinned))
    })
  },
  paintPlayback() {
    this.el.querySelectorAll('[data-play]').forEach(button => {
      const playing = button.dataset.play === this.player
      button.textContent = playing ? 'Ⅱ Pause' : '▶ Play'
      button.setAttribute('aria-pressed', String(playing))
      button.disabled = this.motion.matches || (button.dataset.play === 'proof' && Number(this.el.dataset.proofCount) === 0)
      button.title = this.motion.matches ? 'Reduced motion: use the step arrows' : ''
    })
  },
  stop() {
    clearTimeout(this.timer)
    this.player = null
    this.paintPlayback()
  },
  advance(name, direction) {
    const current = Number(name === 'proof' ? this.el.dataset.stage : this.el.dataset.environmentPosition)
    const max = name === 'proof' ? Number(this.el.dataset.proofCount) - 1 : 8
    const position = Math.max(0, Math.min(max, current + direction))
    if (position === current) return false
    this.pushEvent(name === 'proof' ? 'proof_stage' : 'environment_scrub', name === 'proof' ? {index:String(position)} : {position:String(position)})
    return true
  },
  tick() {
    if (!this.player) return
    if (!this.advance(this.player, 1)) return this.stop()
    this.timer = setTimeout(() => this.tick(), 1500)
  },
}
