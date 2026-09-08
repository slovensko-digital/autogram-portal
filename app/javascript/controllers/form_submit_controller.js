import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submitButton"]
  static values = { pendingText: String }

  handleSubmit() {
    const turboFrame = this.element.closest('turbo-frame')

    if (this.hasSubmitButtonTarget && this.hasPendingTextValue) {
      this.submitButtonTarget.value = this.pendingTextValue
    }

    if (turboFrame) {
      const allButtons = turboFrame.querySelectorAll('button, input[type="submit"]')
      allButtons.forEach(button => {
        button.disabled = true
        button.classList.add('opacity-50', 'cursor-not-allowed')
        button.classList.remove('hover:bg-indigo-700', 'hover:bg-blue-500')
      })
    }
  }
}
