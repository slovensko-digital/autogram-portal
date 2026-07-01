import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["page", "stamp", "pageField", "pageNumber", "previewFrame", "xField", "yField", "widthField", "heightField", "summary", "customText", "contentMode", "stampText", "imageInput", "imagePreview", "existingFieldsLayer"]
  static values = {
    existingFields: { type: Array, default: [] },
    pageWidth: { type: Number, default: 595 },
    pageHeight: { type: Number, default: 842 },
    x: { type: Number, default: 40 },
    y: { type: Number, default: 40 },
    width: { type: Number, default: 256 },
    height: { type: Number, default: 52 },
    mandatoryText: { type: String, default: "" },
    mandatoryTextJoiner: { type: String, default: "\n" },
    locked: { type: Boolean, default: false },
    maxWidth: { type: Number, default: 256 },
    maxHeight: { type: Number, default: 200 }
  }

  connect() {
    this.mode = null
    this.renderFromPdfValues()
    this.updateFields()
    this.updateContent()
    this.renderExistingFields()
    this.refreshPreviewFrame()
  }

  startDrag(event) {
    if (this.lockedValue) return
    if (event.target.dataset.visualStampHandle === "resize") return

    event.preventDefault()
    this.startInteraction(event, "drag")
  }

  startResize(event) {
    if (this.lockedValue) return
    event.preventDefault()
    event.stopPropagation()
    this.startInteraction(event, "resize")
  }

  startInteraction(event, mode) {
    this.mode = mode
    this.pointerStart = { x: event.clientX, y: event.clientY }
    this.rectStart = this.currentStampRect()

    document.addEventListener("pointermove", this.move)
    document.addEventListener("pointerup", this.stop)
    this.stampTarget.setPointerCapture?.(event.pointerId)
  }

  move = (event) => {
    if (!this.mode) return

    const pageRect = this.pageTarget.getBoundingClientRect()
    const dx = event.clientX - this.pointerStart.x
    const dy = event.clientY - this.pointerStart.y
    const minWidth = 120
    const minHeight = 36
    const maxWidth = Math.min(pageRect.width - this.rectStart.left, this.maxWidthValue * (pageRect.width / this.pageWidthValue))
    const maxHeight = Math.min(pageRect.height - this.rectStart.top, this.maxHeightValue * (pageRect.height / this.pageHeightValue))

    let next = { ...this.rectStart }

    if (this.mode === "drag") {
      next.left = this.clamp(this.rectStart.left + dx, 0, pageRect.width - this.rectStart.width)
      next.top = this.clamp(this.rectStart.top + dy, 0, pageRect.height - this.rectStart.height)
    } else {
      next.width = this.clamp(this.rectStart.width + dx, minWidth, maxWidth)
      next.height = this.clamp(this.rectStart.height + dy, minHeight, maxHeight)
    }

    this.applyPreviewRect(next)
    this.updateFields()
  }

  stop = () => {
    this.mode = null
    document.removeEventListener("pointermove", this.move)
    document.removeEventListener("pointerup", this.stop)
  }

  renderFromPdfValues() {
    const pageRect = this.pageTarget.getBoundingClientRect()
    const scaleX = pageRect.width / this.pageWidthValue
    const scaleY = pageRect.height / this.pageHeightValue
    const width = Math.min(this.widthValue, this.maxWidthValue)
    const height = Math.min(this.heightValue, this.maxHeightValue)

    this.applyPreviewRect({
      left: this.xValue * scaleX,
      top: pageRect.height - ((this.yValue + height) * scaleY),
      width: width * scaleX,
      height: height * scaleY
    })
  }

  applyPreviewRect(rect) {
    this.stampTarget.style.left = `${rect.left}px`
    this.stampTarget.style.top = `${rect.top}px`
    this.stampTarget.style.width = `${rect.width}px`
    this.stampTarget.style.height = `${rect.height}px`
  }

  currentStampRect() {
    return {
      left: this.stampTarget.offsetLeft,
      top: this.stampTarget.offsetTop,
      width: this.stampTarget.offsetWidth,
      height: this.stampTarget.offsetHeight
    }
  }

  updateFields() {
    const pageRect = this.pageTarget.getBoundingClientRect()
    const stampRect = this.currentStampRect()
    const scaleX = this.pageWidthValue / pageRect.width
    const scaleY = this.pageHeightValue / pageRect.height
    const page = this.currentPageNumber()

    const x = stampRect.left * scaleX
    const y = this.pageHeightValue - ((stampRect.top + stampRect.height) * scaleY)
    const width = stampRect.width * scaleX
    const height = stampRect.height * scaleY

    this.pageFieldTarget.value = page
    this.xFieldTarget.value = this.round(x)
    this.yFieldTarget.value = this.round(y)
    this.widthFieldTarget.value = this.round(width)
    this.heightFieldTarget.value = this.round(height)

    if (this.hasSummaryTarget) {
      this.summaryTarget.textContent = `${Math.round(width)} x ${Math.round(height)} pt, x ${Math.round(x)}, y ${Math.round(y)}`
    }
  }

  pageChanged() {
    this.pageFieldTarget.value = this.currentPageNumber()
    this.renderExistingFields()
    this.refreshPreviewFrame()
  }

  renderExistingFields() {
    if (!this.hasExistingFieldsLayerTarget) return

    this.existingFieldsLayerTarget.replaceChildren()

    if (!this.existingFieldsValue.length) return

    const pageRect = this.pageTarget.getBoundingClientRect()
    const scaleX = pageRect.width / this.pageWidthValue
    const scaleY = pageRect.height / this.pageHeightValue
    const currentPage = Number(this.currentPageNumber())

    this.existingFieldsValue
      .filter((field) => Number(field.page) === currentPage)
      .forEach((field) => {
        const overlay = document.createElement("div")
        overlay.className = "absolute rounded border border-amber-500 bg-amber-100/80 p-2 shadow-sm"
        overlay.style.left = `${Number(field.x) * scaleX}px`
        overlay.style.top = `${pageRect.height - ((Number(field.y) + Number(field.height)) * scaleY)}px`
        overlay.style.width = `${Number(field.width) * scaleX}px`
        overlay.style.height = `${Number(field.height) * scaleY}px`

        const label = document.createElement("div")
        label.className = "text-[10px] font-medium text-amber-900"
        label.textContent = field.recipientName
        overlay.appendChild(label)

        this.existingFieldsLayerTarget.appendChild(overlay)
      })
  }

  updateContent() {
    const imageMode = this.selectedContentMode() === "image"
    const customText = this.hasCustomTextTarget ? this.customTextTarget.value.trim() : ""
    const contentText = imageMode ? "" : customText
    let text = contentText

    if (this.mandatoryTextValue) {
      text = contentText.length > 0
        ? `${this.mandatoryTextValue}${this.mandatoryTextJoinerValue}${contentText}`
        : this.mandatoryTextValue
    }

    if (this.hasStampTextTarget) {
      this.stampTextTarget.textContent = text
      this.stampTextTarget.classList.toggle("hidden", text.length === 0)
    }

    if (this.hasImagePreviewTarget) {
      this.imagePreviewTarget.classList.toggle("hidden", !imageMode || !this.imagePreviewTarget.src)
    }
  }

  imageChanged() {
    const file = this.imageInputTarget.files[0]
    if (file) {
      this.imagePreviewTarget.src = URL.createObjectURL(file)
    }

    this.contentModeTargets.find((input) => input.value === "image").checked = true
    this.updateContent()
  }

  selectedContentMode() {
    const selected = this.contentModeTargets.find((input) => input.checked)
    return selected ? selected.value : "text"
  }

  currentPageNumber() {
    if (this.hasPageNumberTarget) {
      return this.pageNumberTarget.value || "1"
    }

    return this.pageFieldTarget.value || "1"
  }

  refreshPreviewFrame() {
    if (!this.hasPreviewFrameTarget) return

    const src = this.previewFrameTarget.dataset.baseSrc
    if (!src) return

    this.previewFrameTarget.src = `${src}#page=${this.currentPageNumber()}&toolbar=0&navpanes=0&scrollbar=0&view=FitH`
  }

  clamp(value, min, max) {
    return Math.min(Math.max(value, min), max)
  }

  round(value) {
    return (Math.round(value * 100) / 100).toString()
  }
}