import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]

  connect() {
    this.updateLink()
  }

  updateLink() {
    const checkedRadio = this.element.querySelector('input[type="radio"]:checked')
    if (checkedRadio && checkedRadio.dataset.url) {
      this.linkTarget.href = checkedRadio.dataset.url
    }
  }
}
