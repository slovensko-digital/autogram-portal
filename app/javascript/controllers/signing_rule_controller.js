import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="signing-rule"
export default class extends Controller {
  static targets = ["thresholdField"]

  connect() {
    this.updateVisibility()
  }

  change() {
    this.updateVisibility()
  }

  updateVisibility() {
    const selected = this.element.querySelector('input[name="bundle[signing_rule]"]:checked')
    const isThreshold = selected?.value === "threshold"
    this.thresholdFieldTarget.classList.toggle("hidden", !isThreshold)
  }
}
