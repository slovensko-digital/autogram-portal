import { Controller } from "@hotwired/stimulus"
import { isMobileDevice } from "utils/device_detection"

export default class extends Controller {
  static targets = ["appUrl", "stateNotInstalled"]

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
    this.setupAppOpenDetection()
    this.redirectToAvmUrl(avmUrl)
  }

  redirectToAvmUrl(avmUrl) {
    const inIframe = window.self !== window.top

    try {
      if (inIframe) {
        window.top.location.href = avmUrl
        console.log("Redirected via window.top (iframe detected)")
      } else {
        window.location.href = avmUrl
        console.log("Redirected via window.location (not in iframe)")
      }
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
  }

  setupAppOpenDetection() {
    let appOpened = false
    let blurTimeout = null

    const onBlur = () => {
      appOpened = true
      clearTimeout(blurTimeout)
    }

    window.addEventListener('blur', onBlur)
    blurTimeout = setTimeout(() => {
      window.removeEventListener('blur', onBlur)
      if (!appOpened) {
        console.log("AVM app did not open - showing install instructions")
        this.showAppNotInstalledError()
      }
    }, 2000)

    const onFocus = () => {
      window.removeEventListener('blur', onBlur)
      window.removeEventListener('focus', onFocus)
      clearTimeout(blurTimeout)
      appOpened = true
    }

    window.addEventListener('focus', onFocus)
  }

  showAppNotInstalledError() {
    if (this.hasStateNotInstalledTarget) {
      this.stateNotInstalledTarget.classList.remove('hidden')
    }
  }
}