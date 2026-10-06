import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="docs-contents"
// Marks the user guide section being read in the table of contents (aria-current).
export default class extends Controller {
  static targets = ["link"]

  connect() {
    this.sections = this.linkTargets
      .map(link => document.getElementById(decodeURIComponent(link.hash.slice(1))))
      .filter(Boolean)
    this.onScroll = this.onScroll.bind(this)
    window.addEventListener("scroll", this.onScroll, { passive: true })
    window.addEventListener("resize", this.onScroll, { passive: true })
    this.update()
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
    window.removeEventListener("resize", this.onScroll)
    if (this.frame) cancelAnimationFrame(this.frame)
  }

  onScroll() {
    if (this.frame) return

    this.frame = requestAnimationFrame(() => {
      this.frame = null
      this.update()
    })
  }

  update() {
    if (this.sections.length === 0) return

    // The current section is the last one whose heading has reached the upper third of the window;
    // at the very bottom of the page it is the last section, however short it is.
    const atBottom = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2
    const threshold = window.innerHeight / 3
    const current = atBottom
      ? this.sections[this.sections.length - 1]
      : this.sections.filter(section => section.getBoundingClientRect().top <= threshold).pop() || this.sections[0]

    this.linkTargets.forEach(link => {
      if (link.hash === `#${current.id}`) {
        link.setAttribute("aria-current", "true")
      } else {
        link.removeAttribute("aria-current")
      }
    })
  }
}
