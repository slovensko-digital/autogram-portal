import { Controller } from "@hotwired/stimulus"

// Copies a value to the clipboard. The button stays enabled (disabling it would drop keyboard focus)
// and the result is announced through the `status` live region.
export default class extends Controller {
  static targets = ["label", "status"]
  static values = {
    text: String
  }

  copyToClipboard(event) {
    event.preventDefault()

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(this.textValue).then(() => {
        this.showFeedback(i18n.t("clipboard.copy_success"))
      }).catch(() => {
        this.showFeedback(i18n.t("clipboard.copy_failure"))
      })
    } else {
      this.showFeedback(i18n.t("clipboard.copy_failure"))
    }
  }

  showFeedback(message) {
    const label = this.hasLabelTarget ? this.labelTarget : null
    if (label) {
      this.originalText ??= label.textContent
      label.textContent = message
    }

    if (this.hasStatusTarget) {
      this.statusTarget.textContent = ""
      requestAnimationFrame(() => { this.statusTarget.textContent = message })
    }

    clearTimeout(this.resetTimeout)
    this.resetTimeout = setTimeout(() => {
      if (label) label.textContent = this.originalText
      if (this.hasStatusTarget) this.statusTarget.textContent = ""
    }, 2000)
  }

  disconnect() {
    clearTimeout(this.resetTimeout)
  }
}
