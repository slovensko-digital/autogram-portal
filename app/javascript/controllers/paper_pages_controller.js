import { Controller } from "@hotwired/stimulus"

const MAX_SIDE = 2400
const JPEG_QUALITY = 0.85
const MAX_UNCHANGED_BYTES = 1.5 * 1024 * 1024
const REFRESH_WAIT_MS = 1500

// Uploads the photos and scans of a paper signature as soon as they are picked or dropped, instead
// of waiting for the "Nahrať" button (which stays for browsers without JavaScript). Photos are
// scaled down and re-encoded as JPEG first: phone cameras take 10+ MB pictures, and HEIC is not
// accepted by the server. The page changes then arrive as a Turbo refresh; if none does, the
// controller visits the page itself.
export default class extends Controller {
  static targets = [ "fallback", "status", "error", "dropzone" ]

  connect() {
    this.fallbackTargets.forEach((button) => { button.style.display = "none" })
    this.uploading = 0
    this.queue = Promise.resolve()
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

    this.uploading += 1
    this.showStatus()
    this.hideError()
    this.queue = this.queue.then(() => this.upload(files)).finally(() => {
      this.uploading -= 1
      this.showStatus()
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
      return this.visitPage()
    }

    if (response.ok) {
      this.waitForRefresh()
    } else if (response.status === 422) {
      const body = await response.json().catch(() => ({}))
      body.error ? this.showError(body.error) : this.visitPage()
    } else {
      // The link expired, the scan was submitted meanwhile, ...: the page itself says so.
      this.visitPage()
    }
  }

  // Scales photos down to MAX_SIDE and converts them to JPEG; everything else is sent unchanged.
  async prepare(file) {
    if (!file.type.startsWith("image/")) return file

    const bitmap = await this.decode(file)
    if (!bitmap) return file

    const longest = Math.max(bitmap.width, bitmap.height)
    const scale = Math.min(1, MAX_SIDE / longest)
    const convertible = file.type === "image/jpeg" || file.type === "image/png"
    if (scale === 1 && convertible && file.size <= MAX_UNCHANGED_BYTES) {
      bitmap.close?.()
      return file
    }

    const canvas = document.createElement("canvas")
    canvas.width = Math.round(bitmap.width * scale)
    canvas.height = Math.round(bitmap.height * scale)
    const context = canvas.getContext("2d")
    context.fillStyle = "#fff"
    context.fillRect(0, 0, canvas.width, canvas.height)
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
    bitmap.close?.()

    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", JPEG_QUALITY))
    if (!blob || (scale === 1 && convertible && blob.size >= file.size)) return file

    return new File([ blob ], file.name.replace(/\.[^.]*$/, "") + ".jpg", { type: "image/jpeg", lastModified: file.lastModified })
  }

  async decode(file) {
    try {
      return await createImageBitmap(file, { imageOrientation: "from-image" })
    } catch (error) {
      return null
    }
  }

  // The model broadcasts a refresh after a change. It replaces the page, which disconnects this
  // controller; when nothing arrived (no cable connection) the page is visited here.
  waitForRefresh() {
    setTimeout(() => {
      if (this.element.isConnected) this.visitPage()
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
