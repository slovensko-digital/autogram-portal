import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="toggle"
export default class extends Controller {
  static targets = ["content", "icon", "textExpanded", "textCollapsed", "iframe"]
  static values = {
    collapsed: { type: Boolean, default: false }
  }

  connect() {
    if (this.collapsedValue) {
      this.hide()
    } else {
      this.loadDeferredIframe()
    }
  }

  toggle(event) {
    event.preventDefault()
    if (this.contentTarget.classList.contains("hidden")) {
      this.show()
    } else {
      this.hide()
    }
  }

  show() {
    this.contentTarget.classList.remove("hidden")
    this.loadDeferredIframe()
    this.iconTarget.classList.add('rotate-180')
    this.textExpandedTarget.classList.remove("hidden")
    this.textCollapsedTarget.classList.add("hidden")
    this.collapsedValue = false
  }

  hide() {
    this.contentTarget.classList.add("hidden")
    this.iconTarget.classList.remove('rotate-180')
    this.textExpandedTarget.classList.add("hidden")
    this.textCollapsedTarget.classList.remove("hidden")
    this.collapsedValue = true
  }

  loadDeferredIframe() {
    if (!this.hasIframeTarget) return

    const src = this.iframeTarget.dataset.src
    if (!src || this.iframeTarget.getAttribute("src")) return

    this.iframeTarget.setAttribute("src", src)
  }
}
