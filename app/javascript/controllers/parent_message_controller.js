import { Controller } from "@hotwired/stimulus"

// Messages already sent from this window, by key.
const postedKeys = new Set()

// Tells the page embedding the portal through sdk.js about a signing result.
// A controller rather than an inline script because Turbo does not run scripts
// that arrive in Turbo Stream broadcasts.
export default class extends Controller {
  static values = { payload: Object, key: String }

  connect() {
    // The same result can arrive both in a response and in a broadcast.
    if (this.hasKeyValue) {
      if (postedKeys.has(this.keyValue)) return
      postedKeys.add(this.keyValue)
    }

    window.parent.postMessage(this.payloadValue, "*")
  }
}
