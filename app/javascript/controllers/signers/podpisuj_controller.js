import { Controller } from "@hotwired/stimulus"
import i18n from "i18n"

export default class extends Controller {
  static targets = ["dropzone", "input", "status", "statusMessage", "error"]
  static values = {
    signedDocumentPath: String
  }

  dragover(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("border-blue-400", "bg-blue-50")
  }

  dragleave(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("border-blue-400", "bg-blue-50")
  }

  drop(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("border-blue-400", "bg-blue-50")
    const file = event.dataTransfer?.files?.[0]
    if (file) this.upload(file)
  }

  fileSelected(event) {
    const file = event.target.files?.[0]
    if (file) this.upload(file)
  }

  async upload(file) {
    this.hideError()
    this.showStatus(i18n.t("signature.preparing"))

    const formData = new FormData()
    formData.append("file", file)

    try {
      const response = await fetch(this.signedDocumentPathValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")
        },
        body: formData
      })

      const result = await response.json().catch(() => ({}))

      if (!response.ok || result.error) {
        this.showError(result.error || i18n.t("errors.signing_failed"))
        return
      }
    } catch (error) {
      console.error("2 Error uploading signed document:", error)
      this.showError(error?.message || i18n.t("errors.signing_failed"))
    }
  }

  showStatus(message) {
    this.statusTarget.classList.remove("hidden")
    this.statusMessageTarget.textContent = message
  }

  showError(message) {
    console.error("Error uploading signed document:", message)
    this.statusTarget.classList.add("hidden")
    this.errorTarget.classList.remove("hidden")
    this.errorTarget.textContent = message
  }

  hideError() {
    this.errorTarget.classList.add("hidden")
    this.errorTarget.textContent = ""
  }
}
