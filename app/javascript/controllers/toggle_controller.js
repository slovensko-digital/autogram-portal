import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="toggle"
export default class extends Controller {
  static targets = ["content", "button", "iconExpanded", "iconCollapsed", "textExpanded", "textCollapsed"]
  static values = {
    collapsed: { type: Boolean, default: false }
  }

  connect() {
    if (this.collapsedValue) {
      this.hide()
    }
  }

  toggle() {
    if (this.contentTarget.classList.contains("hidden")) {
      this.show()
    } else {
      this.hide()
    }
  }

  show() {
    this.contentTarget.classList.remove("hidden")
    this.iconExpandedTarget.classList.remove("hidden")
    this.iconCollapsedTarget.classList.add("hidden")
    this.textExpandedTarget.classList.remove("hidden")
    this.textCollapsedTarget.classList.add("hidden")
    this.collapsedValue = false
  }

  hide() {
    this.contentTarget.classList.add("hidden")
    this.iconExpandedTarget.classList.add("hidden")
    this.iconCollapsedTarget.classList.remove("hidden")
    this.textExpandedTarget.classList.add("hidden")
    this.textCollapsedTarget.classList.remove("hidden")
    this.collapsedValue = true
  }
}
