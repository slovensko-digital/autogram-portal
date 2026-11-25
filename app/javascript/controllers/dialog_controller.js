import { Controller } from "@hotwired/stimulus"

// Opens a native <dialog> as a modal; Escape or a close button closes it again.
export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    event.preventDefault()
    this.dialogTarget.showModal()
  }

  close(event) {
    event?.preventDefault()
    if (this.dialogTarget.open) this.dialogTarget.close()
  }
}
