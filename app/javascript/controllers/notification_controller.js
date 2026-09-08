import { Controller } from "@hotwired/stimulus"

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

    this.remainingTime = 5000
    this.resume()
  }

  disconnect() {
    window.cancelAnimationFrame(this.enterFrame)
    this.clearTimer()
  }

  close() {
    this.element.remove()
  }

  pause() {
    if (!this.timeout) return

    this.remainingTime -= Date.now() - this.startedAt
    this.clearTimer()
  }

  resume() {
    if (this.timeout || this.remainingTime <= 0) return

    this.startedAt = Date.now()
    this.timeout = window.setTimeout(() => this.close(), this.remainingTime)
  }

  clearTimer() {
    if (!this.timeout) return

    window.clearTimeout(this.timeout)
    this.timeout = null
  }
}