import { Controller } from "@hotwired/stimulus"
import { isMobileDevice } from "utils/device_detection"

export default class extends Controller {
  static targets = ["submitButton"]

  connect() {
    console.log("Eidentita signer controller connected")
  }

  sign(event) {
    console.log("Eidentita sign method triggered")
    if (isMobileDevice()) {
      console.log("Mobile device detected, handling eIdentita signing")
      event.preventDefault()
      this.submitAndRedirect()
    }
  }

  async submitAndRedirect() {
    try {
      const response = await fetch(this.element.href, {
        headers: {
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (response.ok) {
        const responseText = await response.text()      
        const eidentitaUrl = this.extractEidentitaUrlFromResponse(responseText)
        if (eidentitaUrl) {
          console.log("Redirecting to Eidentita URL:", eidentitaUrl)
          this.redirectToEidentitaUrl(eidentitaUrl)
        } else {
          console.log("Could not extract Eidentita URL, falling back to normal flow")
          this.showError(i18n.t('errors.signing_failed'))
          window.location.reload()
        }
      } else {
        console.error("Form submission failed:", response.status, response.statusText)
        this.showError(i18n.t('errors.signing_failed'))
      }
    } catch (error) {
      console.error("Error submitting form:", error)
      this.showError(i18n.t('errors.network_error'))
    }
  }

  extractEidentitaUrlFromResponse(responseText) {
    const matches = responseText.match(/href="(sk\.minv\.sca:\/\/sign\?[^"]+)"/g)
    if (matches && matches.length > 0) {
    let url = matches[0]
    
    if (url.includes('="')) {
        url = url.split('"')[1]
    } else if (url.includes("='")) {
        url = url.split("'")[1]
    }
    
    if (url.startsWith('sk.minv.sca://')) {
        url = this.decodeHtmlEntities(url)
        console.log("Extracted eIdentita URL:", url)
        return url
    }
    }
    
    return null
  }

  decodeHtmlEntities(text) {
    const tempElement = document.createElement('div')
    tempElement.innerHTML = text
    return tempElement.textContent || tempElement.innerText || text
  }

  showError(message) {
    this.resetParentSignButton()
    alert(message)
  }

  resetParentSignButton() {
    const parentElement = this.element.closest('[data-controller*="signature-method-selector"]')
    if (parentElement) {
      const controller = this.application.getControllerForElementAndIdentifier(
        parentElement, 
        'signature-method-selector'
      )
      if (controller && typeof controller.setSignButtonLoading === 'function') {
        controller.setSignButtonLoading(false)
      }
    }
  }

  redirectToEidentitaUrl(eidentitaUrl) {
    const inIframe = window.self !== window.top
    this.setupAppOpenDetection()

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
    this.resetParentSignButton()

    const message = i18n.t('signature.eidentita_not_installed')
    const installIosText = i18n.t('signature.eidentita_install_ios')
    const installAndroidText = i18n.t('signature.eidentita_install_android')
    const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream
    const isAndroid = /Android/.test(navigator.userAgent)
    const iosAppStoreUrl = 'https://apps.apple.com/sk/app/eidentita/id1628291994'
    const androidPlayStoreUrl = 'https://play.google.com/store/apps/details?id=sk.minv.eidentita'

    if (isIOS) {
      if (confirm(message + '\n\n' + installIosText)) {
        window.open(iosAppStoreUrl, '_blank')
      }
    } else if (isAndroid) {
      if (confirm(message + '\n\n' + installAndroidText)) {
        window.open(androidPlayStoreUrl, '_blank')
      }
    } else {
      alert(message)
    }
  }
}
