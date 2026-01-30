import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        text: String
    }

  copyToClipboard(event) {
    event.preventDefault()

    const button = event.currentTarget

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(this.textValue).then(() => {
        this.showCopiedFeedback(button)
      }).catch(() => {
        this.showCopyError(button)
      })
    } else {
      this.showCopyError(button)
    }
  }

  showCopiedFeedback(button) {
    const originalText = button.innerText
    button.innerText = i18n.t("clipboard.copied")
    button.disabled = true

    setTimeout(() => {
      button.innerText = originalText
      button.disabled = false
    }, 2000)
  }

  showCopyError(button) {
    const originalText = button.innerText
    button.innerText = i18n.t("clipboard.copy_failure")
    button.disabled = true

    setTimeout(() => {
      button.innerText = originalText
      button.disabled = false
    }, 2000)
  }
}
