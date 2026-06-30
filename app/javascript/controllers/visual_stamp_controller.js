import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["page", "stamp", "pageField", "xField", "yField", "widthField", "heightField", "textField", "summary"]
  static values = {
    pageWidth: { type: Number, default: 595 },
    pageHeight: { type: Number, default: 842 },
    x: { type: Number, default: 40 },
    y: { type: Number, default: 40 },
    width: { type: Number, default: 260 },
    height: { type: Number, default: 52 }
  }

  connect() {
    this.mode = null
    this.renderFromPdfValues()
    this.updateFields()
  }

  startDrag(event) {
    if (event.target.dataset.visualStampHandle === "resize") return

    event.preventDefault()
    this.startInteraction(event, "drag")
  }

  startResize(event) {
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

    let next = { ...this.rectStart }

    if (this.mode === "drag") {
      next.left = this.clamp(this.rectStart.left + dx, 0, pageRect.width - this.rectStart.width)
      next.top = this.clamp(this.rectStart.top + dy, 0, pageRect.height - this.rectStart.height)
    } else {
      next.width = this.clamp(this.rectStart.width + dx, minWidth, pageRect.width - this.rectStart.left)
      next.height = this.clamp(this.rectStart.height + dy, minHeight, pageRect.height - this.rectStart.top)
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

    this.applyPreviewRect({
      left: this.xValue * scaleX,
      top: pageRect.height - ((this.yValue + this.heightValue) * scaleY),
      width: this.widthValue * scaleX,
      height: this.heightValue * scaleY
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

    const x = stampRect.left * scaleX
    const y = this.pageHeightValue - ((stampRect.top + stampRect.height) * scaleY)
    const width = stampRect.width * scaleX
    const height = stampRect.height * scaleY

    this.pageFieldTarget.value = "1"
    this.xFieldTarget.value = this.round(x)
    this.yFieldTarget.value = this.round(y)
    this.widthFieldTarget.value = this.round(width)
    this.heightFieldTarget.value = this.round(height)

    if (this.hasSummaryTarget) {
      this.summaryTarget.textContent = `${Math.round(width)} x ${Math.round(height)} pt, x ${Math.round(x)}, y ${Math.round(y)}`
    }
  }

  clamp(value, min, max) {
    return Math.min(Math.max(value, min), max)
  }

  round(value) {
    return (Math.round(value * 100) / 100).toString()
  }
}