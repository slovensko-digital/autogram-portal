import { Controller } from "@hotwired/stimulus"

const MAX_SIDE = 2400
const JPEG_QUALITY = 0.85
const REFRESH_WAIT_MS = 1500

// Uploads the photos and scans of a paper signature as soon as they are picked or dropped, instead
// of waiting for the "Nahrať" button (which stays for browsers without JavaScript). Photos are
// scaled down and re-encoded as JPEG first: phone cameras take 10+ MB pictures, HEIC is not
// accepted by the server, and the server joins photos into a PDF without honouring the EXIF
// orientation, so every photo is redrawn upright. The page changes then arrive as a Turbo refresh; if none does, the
// controller visits the page itself.
export default class extends Controller {
  static targets = [ "fallback", "status", "error", "dropzone", "input" ]
  static values = { failed: String }

  connect() {
    this.fallbackTargets.forEach((button) => { button.style.display = "none" })
    // The dropzone around it is the visible control; the input stays for keyboards and screen readers.
    this.inputTargets.forEach((input) => { input.className = "sr-only" })
    this.uploading = 0
    this.queue = Promise.resolve()
    this.refreshed = false
    this.markRefreshed = () => { this.refreshed = true }
    // A refresh replaces the page (this controller disconnects) or morphs it (it stays).
    document.addEventListener("turbo:render", this.markRefreshed)
    document.addEventListener("turbo:morph", this.markRefreshed)
  }

  disconnect() {
    clearTimeout(this.refreshTimer)
    document.removeEventListener("turbo:render", this.markRefreshed)
    document.removeEventListener("turbo:morph", this.markRefreshed)
  }

  pick(event) {
    const input = event.target
    if (!(input instanceof HTMLInputElement) || input.type !== "file") return

    const files = Array.from(input.files)
    input.value = ""
    this.enqueue(files)
  }

  dragOver(event) {
    if (!this.hasFiles(event)) return
    event.preventDefault()
    this.dropzoneTargets.forEach((zone) => zone.setAttribute("data-dragging", ""))
  }

  dragLeave(event) {
    if (event.relatedTarget && this.element.contains(event.relatedTarget)) return
    this.dropzoneTargets.forEach((zone) => zone.removeAttribute("data-dragging"))
  }

  drop(event) {
    if (!this.hasFiles(event)) return
    event.preventDefault()
    this.dropzoneTargets.forEach((zone) => zone.removeAttribute("data-dragging"))
    this.enqueue(Array.from(event.dataTransfer.files))
  }

  hasFiles(event) {
    return event.dataTransfer && Array.from(event.dataTransfer.types || []).includes("Files")
  }

  // Uploads one after another so the pages keep the order they were picked in.
  enqueue(files) {
    if (files.length === 0) return

    clearTimeout(this.refreshTimer)
    this.refreshed = false
    this.uploading += 1
    this.showStatus()
    this.hideError()
    // A failing upload must not stop the later ones: the queue itself never rejects.
    this.queue = this.queue
      .then(() => this.upload(files))
      .catch(() => this.showError(this.failedValue))
      .finally(() => {
        this.uploading -= 1
        this.showStatus()
        if (this.uploading === 0 && this.pendingRefresh) this.waitForRefresh()
      })
  }

  async upload(files) {
    const form = new FormData()
    for (const file of files) {
      const prepared = await this.prepare(file)
      form.append("files[]", prepared, prepared.name)
    }

    let response
    try {
      response = await fetch(this.element.action, {
        method: "POST",
        body: form,
        credentials: "same-origin",
        headers: { "Accept": "application/json", "X-CSRF-Token": this.csrfToken() }
      })
    } catch (error) {
      this.pendingRefresh = false
      return this.visitPage()
    }

    if (response.ok) {
      this.pendingRefresh = true
    } else if (response.status === 422) {
      const body = await response.json().catch(() => ({}))
      body.error ? this.showError(body.error) : this.visitPage()
    } else {
      // The link expired, the scan was submitted meanwhile, ...: the page itself says so.
      this.visitPage()
    }
  }

  // Redraws photos upright, at most MAX_SIDE on the longest side, as JPEG; everything else (PDFs,
  // images the browser cannot decode) is sent unchanged.
  async prepare(file) {
    if (!file.type.startsWith("image/")) return file

    try {
      const image = await this.decode(file)
      if (!image) return file

      const scale = Math.min(1, MAX_SIDE / Math.max(image.width, image.height))
      const canvas = document.createElement("canvas")
      canvas.width = Math.max(1, Math.round(image.width * scale))
      canvas.height = Math.max(1, Math.round(image.height * scale))
      const context = canvas.getContext("2d")
      if (!context) return file

      context.fillStyle = "#fff"
      context.fillRect(0, 0, canvas.width, canvas.height)
      context.drawImage(image.source, 0, 0, canvas.width, canvas.height)
      image.release()

      const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", JPEG_QUALITY))
      if (!blob) return file

      return new File([ blob ], file.name.replace(/\.[^.]*$/, "") + ".jpg", { type: "image/jpeg", lastModified: file.lastModified })
    } catch (error) {
      return file
    }
  }

  // Decodes with the EXIF orientation applied. Browsers without the createImageBitmap options
  // (older Safari) decode through an <img>, which is drawn upright by modern browsers.
  async decode(file) {
    try {
      const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
      return { source: bitmap, width: bitmap.width, height: bitmap.height, release: () => bitmap.close?.() }
    } catch (error) {
      // fall through to the image element
    }

    const url = URL.createObjectURL(file)
    try {
      const element = new Image()
      element.src = url
      await element.decode()
      return { source: element, width: element.naturalWidth, height: element.naturalHeight, release: () => URL.revokeObjectURL(url) }
    } catch (error) {
      URL.revokeObjectURL(url)
      return null
    }
  }

  // The model broadcasts a refresh after a change. When none was applied shortly after the last
  // upload (no cable connection), the page is visited here. One timer at a time; a new upload
  // cancels it.
  waitForRefresh() {
    this.pendingRefresh = false
    clearTimeout(this.refreshTimer)
    this.refreshTimer = setTimeout(() => {
      if (this.uploading === 0 && !this.refreshed && this.element.isConnected) this.visitPage()
    }, REFRESH_WAIT_MS)
  }

  visitPage() {
    window.Turbo.visit(window.location.href, { action: "replace" })
  }

  showStatus() {
    this.statusTarget.classList.toggle("hidden", this.uploading === 0)
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  hideError() {
    this.errorTarget.classList.add("hidden")
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
