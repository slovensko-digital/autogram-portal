import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Attached to the <turbo-cable-stream-source> of a pending session. The result of the session is broadcast to it,
// but phone browsers drop the WebSocket while the signer is in the signing app and lose broadcasts sent meanwhile.
// So the page asks for the state of the session whenever the stream (re)connects and the page becomes visible again.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.observer = new MutationObserver(() => {
      if (this.element.hasAttribute("connected")) this.check()
    })
    this.observer.observe(this.element, { attributes: true, attributeFilter: ["connected"] })

    this.checkWhenVisible = () => {
      if (document.visibilityState === "visible") this.check()
    }
    document.addEventListener("visibilitychange", this.checkWhenVisible)

    if (this.element.hasAttribute("connected")) this.check()
  }

  disconnect() {
    this.observer.disconnect()
    document.removeEventListener("visibilitychange", this.checkWhenVisible)
  }

  async check() {
    try {
      const response = await fetch(this.urlValue, { headers: { Accept: "text/vnd.turbo-stream.html" } })
      // A pending session answers 204; anything else but a Turbo Stream (e.g. a redirect to sign in) is ignored.
      if (response.ok && response.headers.get("Content-Type")?.startsWith("text/vnd.turbo-stream.html")) {
        Turbo.renderStreamMessage(await response.text())
      }
    } catch (error) {
      console.log("Session state check failed:", error)
    }
  }
}
