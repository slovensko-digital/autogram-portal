import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "submit"]
  static values = { phrase: String }

  connect() {
    this.update()
  }

  update() {
    const matches = this.inputTarget.value.trim() === this.phraseValue
    this.submitTarget.disabled = !matches
    this.submitTarget.classList.toggle("opacity-50", !matches)
    this.submitTarget.classList.toggle("cursor-not-allowed", !matches)
  }
}
