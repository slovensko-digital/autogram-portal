import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Pages cached before a change (e.g. the document still waiting for this signature) would otherwise
// flash as the preview of the next visit to them.
export default class extends Controller {
  connect() {
    Turbo.cache.clear()
  }
}
