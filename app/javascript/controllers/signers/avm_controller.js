import { Controller } from "@hotwired/stimulus"
import { isMobileDevice } from "utils/device_detection"

export default class extends Controller {
  static targets = ["appUrl"]

  connect() {
    console.log("AVM signer controller connected")
    if (isMobileDevice() && this.hasAppUrlTarget) {
      this.openApp()
    }
  }

  openApp() {
    const avmUrl = this.appUrlTarget.href
    if (!avmUrl) return

    console.log("Auto-opening AVM app on mobile:", avmUrl)
    this.redirectToAvmUrl(avmUrl)
  }

  redirectToAvmUrl(avmUrl) {
    const inIframe = window.self !== window.top

    if (inIframe) {
      try {
        window.top.location.href = avmUrl
        console.log("Redirected via window.top (iframe detected)")
      } catch (e) {
        console.log("Cross-origin iframe detected, attempting alternative redirect methods")

        const opened = window.open(avmUrl, '_blank')

        if (!opened || opened.closed || typeof opened.closed === 'undefined') {
          console.log("window.open blocked, trying link click method")
          const link = document.createElement('a')
          link.href = avmUrl
          link.target = '_blank'
          link.rel = 'noopener noreferrer'
          document.body.appendChild(link)
          link.click()
          document.body.removeChild(link)
        }
      }
    } else {
      window.location.href = avmUrl
      console.log("Redirected via window.location (not in iframe)")
    }
  }
}