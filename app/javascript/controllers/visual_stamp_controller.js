import { Controller } from "@hotwired/stimulus"
import * as pdfjsLib from "pdfjs-dist"

const PDFJS_WORKER_URL = "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.worker.min.mjs"
const MIN_WIDTH = 120
const MIN_HEIGHT = 36

pdfjsLib.GlobalWorkerOptions.workerSrc = PDFJS_WORKER_URL

export default class extends Controller {
  static targets = ["page", "stamp", "pageField", "pageNumber", "xField", "yField", "widthField", "heightField", "summary", "customText", "contentMode", "stampText", "imageInput", "imagePreview", "existingFieldsLayer", "pdfCanvas", "previewFallback", "previewLink", "drawingPanel", "drawingPad", "drawingData", "drawingStatus"]
  static values = {
    existingFields: { type: Array, default: [] },
    pageWidth: { type: Number, default: 595 },
    pageHeight: { type: Number, default: 842 },
    x: { type: Number, default: 40 },
    y: { type: Number, default: 40 },
    width: { type: Number, default: 200 },
    height: { type: Number, default: 52 },
    mandatoryText: { type: String, default: "" },
    mandatoryTextJoiner: { type: String, default: "\n" },
    hideMandatoryTextWhenGraphic: { type: Boolean, default: false },
    locked: { type: Boolean, default: false },
    maxWidth: { type: Number, default: 255 },
    maxHeight: { type: Number, default: 200 },
    previewUrl: { type: String, default: "" }
  }

  connect() {
    this.mode = null
    this.pdfDocument = null
    this.pdfRenderTask = null
    this.pdfLoadingTask = null
    this.uploadedImageUrl = null
    this.isDrawing = false
    this.drawingCleared = false
    this.resizeTimeout = null
    this.bodyOverflow = null
    this.bodyTouchAction = null
    this.handleWindowResize = this.handleWindowResize.bind(this)

    this.renderFromPdfValues()
    this.updateFields()
    this.updateContent()
    this.setupDrawingPad()
    this.renderExistingFields()
    this.loadPdfPreview()

    window.addEventListener("resize", this.handleWindowResize)
  }

  disconnect() {
    this.stop()
    this.stopDrawing()
    this.revokeUploadedImageUrl()
    this.pdfRenderTask?.cancel?.()
    this.pdfLoadingTask?.destroy?.()
    window.removeEventListener("resize", this.handleWindowResize)
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
    this.bodyOverflow = document.body.style.overflow
    this.bodyTouchAction = document.body.style.touchAction
    document.body.style.overflow = "hidden"
    document.body.style.touchAction = "none"

    document.addEventListener("pointermove", this.move)
    document.addEventListener("pointerup", this.stop)
    document.addEventListener("pointercancel", this.stop)
    this.stampTarget.setPointerCapture?.(event.pointerId)
  }

  move = (event) => {
    if (!this.mode) return

    event.preventDefault()

    const pageRect = this.pageTarget.getBoundingClientRect()
    const dx = event.clientX - this.pointerStart.x
    const dy = event.clientY - this.pointerStart.y
    const maxWidth = Math.min(pageRect.width - this.rectStart.left, this.maxWidthValue * (pageRect.width / this.pageWidthValue))
    const maxHeight = Math.min(pageRect.height - this.rectStart.top, this.maxHeightValue * (pageRect.height / this.pageHeightValue))

    let next = { ...this.rectStart }

    if (this.mode === "drag") {
      next.left = this.clamp(this.rectStart.left + dx, 0, pageRect.width - this.rectStart.width)
      next.top = this.clamp(this.rectStart.top + dy, 0, pageRect.height - this.rectStart.height)
    } else {
      next.width = this.clamp(this.rectStart.width + dx, MIN_WIDTH, maxWidth)
      next.height = this.clamp(this.rectStart.height + dy, MIN_HEIGHT, maxHeight)
    }

    this.applyPreviewRect(next)
    this.updateFields()
  }

  stop = () => {
    this.mode = null
    document.removeEventListener("pointermove", this.move)
    document.removeEventListener("pointerup", this.stop)
    document.removeEventListener("pointercancel", this.stop)

    if (this.bodyOverflow !== null) {
      document.body.style.overflow = this.bodyOverflow
      this.bodyOverflow = null
    }

    if (this.bodyTouchAction !== null) {
      document.body.style.touchAction = this.bodyTouchAction
      this.bodyTouchAction = null
    }
  }

  renderFromPdfValues() {
    const pageRect = this.pageTarget.getBoundingClientRect()
    if (pageRect.width === 0 || pageRect.height === 0) return

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
    if (pageRect.width === 0 || pageRect.height === 0) return

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
    this.syncPageNumber(this.currentPageNumber())

    if (this.hasPdfCanvasTarget && this.previewUrlValue) {
      this.loadPdfPreview()
      return
    }

    this.renderExistingFields()
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
    const contentMode = this.selectedContentMode()
    const graphicMode = contentMode === "image" || contentMode === "draw"
    const customText = this.hasCustomTextTarget ? this.customTextTarget.value.trim() : ""
    const contentText = graphicMode ? "" : customText
    let text = contentText

    if (graphicMode && this.hideMandatoryTextWhenGraphicValue) {
      text = ""
    } else if (this.mandatoryTextValue) {
      text = contentText.length > 0
        ? `${this.mandatoryTextValue}${this.mandatoryTextJoinerValue}${contentText}`
        : this.mandatoryTextValue
    }

    if (this.hasStampTextTarget) {
      this.stampTextTarget.textContent = text
      this.stampTextTarget.classList.toggle("hidden", text.length === 0)
    }

    if (this.hasImagePreviewTarget) {
      const source = this.graphicPreviewSource(contentMode)
      if (source) {
        this.imagePreviewTarget.src = source
      }

      this.imagePreviewTarget.classList.toggle("hidden", !graphicMode || !source)
    }

    if (this.hasDrawingPanelTarget) {
      this.drawingPanelTarget.classList.toggle("hidden", contentMode !== "draw")
    }
  }

  imageChanged() {
    const file = this.imageInputTarget.files[0]
    if (file) {
      this.revokeUploadedImageUrl()
      this.uploadedImageUrl = URL.createObjectURL(file)
    }

    this.contentModeTargets.find((input) => input.value === "image").checked = true
    this.updateContent()
  }

  contentModeChanged() {
    this.updateContent()

    if (this.selectedContentMode() === "draw") {
      requestAnimationFrame(() => {
        this.resizeDrawingPad()
        this.seedDrawingPad()
      })
    }
  }

  startDrawing(event) {
    if (this.selectedContentMode() !== "draw") return

    event.preventDefault()
    this.seedDrawingPad()
    this.isDrawing = true

    const context = this.drawingPadTarget.getContext("2d")
    const point = this.drawingPoint(event)
    context.beginPath()
    context.moveTo(point.x, point.y)
    context.lineTo(point.x + 0.01, point.y + 0.01)
    context.stroke()

    this.drawingPadTarget.setPointerCapture?.(event.pointerId)
  }

  draw(event) {
    if (!this.isDrawing) return

    event.preventDefault()

    const context = this.drawingPadTarget.getContext("2d")
    const point = this.drawingPoint(event)
    context.lineTo(point.x, point.y)
    context.stroke()
  }

  stopDrawing() {
    if (!this.isDrawing) return

    this.isDrawing = false
    this.persistDrawing()
  }

  clearDrawing() {
    if (!this.hasDrawingPadTarget) return

    const context = this.drawingPadTarget.getContext("2d")
    context.clearRect(0, 0, this.drawingPadTarget.width, this.drawingPadTarget.height)
    this.drawingCleared = true

    if (this.hasDrawingDataTarget) {
      this.drawingDataTarget.value = ""
    }

    if (this.hasDrawingStatusTarget) {
      this.drawingStatusTarget.textContent = this.drawingStatusTarget.dataset.emptyLabel || ""
    }

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

  async loadPdfPreview() {
    if (!this.hasPdfCanvasTarget || !this.previewUrlValue) return

    try {
      if (!this.pdfDocument || this.pdfDocumentUrl !== this.previewUrlValue) {
        this.pdfLoadingTask?.destroy?.()
        this.pdfLoadingTask = pdfjsLib.getDocument(this.previewUrlValue)
        this.pdfDocument = await this.pdfLoadingTask.promise
        this.pdfDocumentUrl = this.previewUrlValue
      }

      const requestedPage = this.clamp(Number(this.currentPageNumber()) || 1, 1, this.pdfDocument.numPages)
      this.syncPageNumber(requestedPage)

      if (this.hasPageNumberTarget) {
        this.pageNumberTarget.max = this.pdfDocument.numPages
      }

      const page = await this.pdfDocument.getPage(requestedPage)
      const baseViewport = page.getViewport({ scale: 1 })
      this.pageWidthValue = baseViewport.width
      this.pageHeightValue = baseViewport.height
      this.pageTarget.style.aspectRatio = `${baseViewport.width} / ${baseViewport.height}`

      const scale = this.pageTarget.clientWidth / baseViewport.width
      const viewport = page.getViewport({ scale })
      const outputScale = window.devicePixelRatio || 1
      const canvas = this.pdfCanvasTarget
      const context = canvas.getContext("2d", { alpha: false })

      canvas.width = Math.floor(viewport.width * outputScale)
      canvas.height = Math.floor(viewport.height * outputScale)
      canvas.style.width = `${viewport.width}px`
      canvas.style.height = `${viewport.height}px`

      context.setTransform(outputScale, 0, 0, outputScale, 0, 0)
      context.clearRect(0, 0, viewport.width, viewport.height)
      context.fillStyle = "#ffffff"
      context.fillRect(0, 0, viewport.width, viewport.height)

      this.pdfRenderTask?.cancel?.()
      this.pdfRenderTask = page.render({ canvasContext: context, viewport })
      await this.pdfRenderTask.promise

      this.togglePreviewFallback(false)
      this.renderFromPdfValues()
      this.updateFields()
      this.renderExistingFields()
    } catch (error) {
      if (error?.name === "RenderingCancelledException") return

      this.togglePreviewFallback(true)
      console.error("Failed to render PDF preview", error)
    }
  }

  handleWindowResize() {
    clearTimeout(this.resizeTimeout)
    this.resizeTimeout = setTimeout(() => {
      if (this.hasDrawingPadTarget) {
        this.resizeDrawingPad()
      }

      if (this.hasPdfCanvasTarget && this.previewUrlValue) {
        this.loadPdfPreview()
      } else {
        this.renderFromPdfValues()
        this.updateFields()
        this.renderExistingFields()
      }
    }, 100)
  }

  setupDrawingPad() {
    if (!this.hasDrawingPadTarget) return

    this.resizeDrawingPad()

    if (this.selectedContentMode() === "draw") {
      this.seedDrawingPad()
    }
  }

  resizeDrawingPad() {
    if (!this.hasDrawingPadTarget) return

    const snapshot = this.hasDrawingDataTarget && this.drawingDataTarget.value
      ? this.drawingDataTarget.value
      : null
    const rect = this.drawingPadTarget.getBoundingClientRect()
    const width = Math.max(Math.floor(rect.width), 1)
    const height = Math.max(Math.floor(rect.height), 1)
    const outputScale = window.devicePixelRatio || 1

    this.drawingPadTarget.width = Math.floor(width * outputScale)
    this.drawingPadTarget.height = Math.floor(height * outputScale)

    const context = this.drawingPadTarget.getContext("2d")
    context.setTransform(outputScale, 0, 0, outputScale, 0, 0)
    context.clearRect(0, 0, width, height)
    context.lineCap = "round"
    context.lineJoin = "round"
    context.strokeStyle = "#111827"
    context.lineWidth = 2.5

    if (snapshot) {
      this.paintDrawing(snapshot)
    }
  }

  seedDrawingPad() {
    if (!this.hasDrawingPadTarget) return
    if (!this.drawingCanvasIsBlank()) return
    if (this.drawingCleared) return

    const snapshot = this.hasDrawingDataTarget && this.drawingDataTarget.value
      ? this.drawingDataTarget.value
      : (this.uploadedImageUrl || this.existingGraphicSource())

    if (snapshot) {
      this.paintDrawing(snapshot)
      return
    }

    if (this.hasDrawingStatusTarget) {
      this.drawingStatusTarget.textContent = this.drawingStatusTarget.dataset.emptyLabel || ""
    }
  }

  async paintDrawing(source) {
    if (!source || !this.hasDrawingPadTarget) return

    const image = await this.loadImage(source)
    const context = this.drawingPadTarget.getContext("2d")
    const canvasWidth = this.drawingPadTarget.width / (window.devicePixelRatio || 1)
    const canvasHeight = this.drawingPadTarget.height / (window.devicePixelRatio || 1)
    const padding = 8
    const scale = Math.min((canvasWidth - (padding * 2)) / image.width, (canvasHeight - (padding * 2)) / image.height)
    const width = image.width * scale
    const height = image.height * scale
    const x = (canvasWidth - width) / 2
    const y = (canvasHeight - height) / 2

    context.clearRect(0, 0, canvasWidth, canvasHeight)
    context.drawImage(image, x, y, width, height)
    this.drawingCleared = false
    this.persistDrawing()
  }

  loadImage(source) {
    return new Promise((resolve, reject) => {
      const image = new Image()
      image.onload = () => resolve(image)
      image.onerror = reject
      image.src = source
    })
  }

  drawingPoint(event) {
    const rect = this.drawingPadTarget.getBoundingClientRect()
    return {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top
    }
  }

  persistDrawing() {
    if (!this.hasDrawingDataTarget || !this.hasDrawingPadTarget) return

    this.drawingDataTarget.value = this.drawingCanvasIsBlank()
      ? ""
      : this.drawingPadTarget.toDataURL("image/png")
    this.drawingCleared = false

    if (this.hasDrawingStatusTarget) {
      this.drawingStatusTarget.textContent = this.drawingDataTarget.value
        ? this.drawingStatusTarget.dataset.filledLabel || ""
        : this.drawingStatusTarget.dataset.emptyLabel || ""
    }

    this.updateContent()
  }

  drawingCanvasIsBlank() {
    const context = this.drawingPadTarget.getContext("2d")
    const pixels = context.getImageData(0, 0, this.drawingPadTarget.width, this.drawingPadTarget.height).data

    for (let index = 3; index < pixels.length; index += 4) {
      if (pixels[index] !== 0) return false
    }

    return true
  }

  graphicPreviewSource(contentMode = this.selectedContentMode()) {
    if (contentMode === "draw") {
      return this.hasDrawingDataTarget ? this.drawingDataTarget.value : ""
    }

    if (contentMode === "image") {
      return this.uploadedImageUrl || this.existingGraphicSource()
    }

    return ""
  }

  existingGraphicSource() {
    if (!this.hasImagePreviewTarget) return ""

    return this.imagePreviewTarget.dataset.existingSrc || ""
  }

  syncPageNumber(pageNumber) {
    const value = pageNumber.toString()
    this.pageFieldTarget.value = value

    if (this.hasPageNumberTarget) {
      this.pageNumberTarget.value = value
    }
  }

  togglePreviewFallback(visible) {
    if (this.hasPreviewFallbackTarget) {
      this.previewFallbackTarget.classList.toggle("hidden", !visible)
    }

    if (visible && this.hasPreviewLinkTarget) {
      this.previewLinkTarget.href = this.previewUrlValue
    }
  }

  revokeUploadedImageUrl() {
    if (!this.uploadedImageUrl) return

    URL.revokeObjectURL(this.uploadedImageUrl)
    this.uploadedImageUrl = null
  }

  clamp(value, min, max) {
    return Math.min(Math.max(value, min), max)
  }

  round(value) {
    return (Math.round(value * 100) / 100).toString()
  }
}