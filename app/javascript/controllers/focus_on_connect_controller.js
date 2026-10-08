import { Controller } from "@hotwired/stimulus"

// Moves focus to content that replaced the focused part of the page, e.g. a signing result arriving
// in a Turbo Stream broadcast. Keyboard users continue from it and screen readers announce it.
// The element needs tabindex="-1" unless it is focusable on its own.
export default class extends Controller {
  connect() {
    this.element.focus()
  }
}
