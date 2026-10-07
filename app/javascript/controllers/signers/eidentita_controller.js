import { Controller } from "@hotwired/stimulus"
import { isPhoneDevice } from "utils/device_detection"

export default class extends Controller {
  static targets = ["appUrl", "stateNotInstalled", "phoneActions", "qrCode", "showQrCodeButton"]

  connect() {
    console.log("Eidentita signer controller connected")
    // Tablets keep the QR code for a phone and do not open the app themselves.
    if (isPhoneDevice() && this.hasAppUrlTarget) {
      this.qrCodeTarget.classList.add('hidden')
      this.phoneActionsTarget.classList.remove('hidden')
      this.openApp()
    }
  }

  showQrCode() {
    this.qrCodeTarget.classList.remove('hidden')
    this.showQrCodeButtonTarget.classList.add('hidden')
    this.appUrlTarget.focus()
  }

  openApp() {
    const eidentitaUrl = this.appUrlTarget.href
    if (!eidentitaUrl) return

    console.log("Auto-opening eIdentita app on mobile:", eidentitaUrl)
    this.setupAppOpenDetection()
    this.redirectToEidentitaUrl(eidentitaUrl)
  }

  redirectToEidentitaUrl(eidentitaUrl) {
    const inIframe = window.self !== window.top

    try {
      if (inIframe) {
        window.top.location.href = eidentitaUrl
        console.log("Redirected via window.top (iframe detected)")
      } else {
        window.location.href = eidentitaUrl
        console.log("Redirected via window.location (not in iframe)")
      }
    } catch (e) {
      console.log("Cross-origin iframe detected, attempting alternative redirect methods")

      const opened = window.open(eidentitaUrl, '_blank')

      if (!opened || opened.closed || typeof opened.closed === 'undefined') {
        console.log("window.open blocked, trying link click method")
        const link = document.createElement('a')
        link.href = eidentitaUrl
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
        console.log("eIdentita app did not open - showing install instructions")
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
