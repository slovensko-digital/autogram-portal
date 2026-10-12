import { Controller } from "@hotwired/stimulus"

// Shows that a submitted form is being processed and blocks repeated submissions. A rich button
// (e.g. a menu item with an icon and a description) marks the part to relabel as the "label" target
// and may swap its "icon" target for a "spinner" target.
export default class extends Controller {
  static targets = ["submitButton", "label", "icon", "spinner"]
  static values = { pendingText: String }

  handleSubmit() {
    const turboFrame = this.element.closest('turbo-frame')

    if (this.hasSubmitButtonTarget && this.hasPendingTextValue) {
      if (this.hasLabelTarget) {
        this.labelTarget.textContent = this.pendingTextValue
      } else if (this.submitButtonTarget.matches('input')) {
        this.submitButtonTarget.value = this.pendingTextValue
      } else {
        this.submitButtonTarget.textContent = this.pendingTextValue
      }
    }

    if (this.hasSpinnerTarget) {
      this.iconTargets.forEach(icon => icon.classList.add('hidden'))
      this.spinnerTarget.classList.remove('hidden')
    }

    if (this.hasSubmitButtonTarget) this.submitButtonTarget.setAttribute('aria-busy', 'true')

    if (turboFrame) {
      const allButtons = turboFrame.querySelectorAll('button, input[type="submit"]')
      allButtons.forEach(button => {
        button.disabled = true
        // The button showing the progress stays readable; the others fade out.
        if (this.hasSpinnerTarget && button === this.submitButtonTarget) {
          button.classList.add('cursor-wait')
        } else {
          button.classList.add('opacity-50', 'cursor-not-allowed')
        }
      })
    }
  }
}
