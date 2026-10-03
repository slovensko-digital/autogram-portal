import { Controller } from "@hotwired/stimulus"

// Result notifications stay visible until the user closes them or the next notification replaces them,
// so that users of screen magnifiers or slower readers do not miss them (WCAG 2.2.1).
export default class extends Controller {
  connect() {
    document.querySelectorAll("[data-notification-overlay]").forEach(notification => {
      if (notification !== this.element) notification.remove()
    })

    this.element.classList.add("opacity-0", "translate-y-2")
    this.enterFrame = window.requestAnimationFrame(() => {
      this.enterFrame = window.requestAnimationFrame(() => {
        this.element.classList.remove("opacity-0", "translate-y-2")
      })
    })
  }

  disconnect() {
    window.cancelAnimationFrame(this.enterFrame)
  }

  close() {
    this.element.remove()
  }
}
