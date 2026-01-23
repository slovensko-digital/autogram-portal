import { Controller } from "@hotwired/stimulus"
import { isMobileDevice } from "utils/device_detection"

export default class extends Controller {
  static targets = ["submitButton"]

  connect() {
    console.log("Eidentita signer controller connected")
  }

  sign(event) {
    this.setButtonLoading(true)
    event.preventDefault()
    this.submitAndRedirect()
  }

  async submitAndRedirect() {
    try {
      const response = await fetch(this.element.action, {
        headers: {
          'Accept': 'text/vnd.turbo-stream.html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (response.ok) {
        const responseText = await response.text()
        
        if (isMobileDevice()) {
          const eidentitaUrl = this.extractEidentitaUrlFromResponse(responseText)
          if (eidentitaUrl) {
            console.log("Redirecting to Eidentita URL:", eidentitaUrl)
            this.redirectToEidentitaUrl(eidentitaUrl)
          } else {
            console.log("Could not extract Eidentita URL, falling back to normal flow")
            Turbo.renderStreamMessage(responseText)
          }
        } else {
          Turbo.renderStreamMessage(responseText)
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
    this.setButtonLoading(false)
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

  setButtonLoading(loading) {
    const button = this.submitButtonTarget
    if (loading) {
      button.disabled = true
      const openingText = i18n.t('signature.opening_eidentita')
      button.innerHTML = `
        <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        <span class="font-semibold">${openingText}</span>
      `
    } else {
      button.disabled = false
      const signText = i18n.t('signature.sign_with_eidentita')
      button.innerHTML = `
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5"
              stroke="currentColor" class="w-5 h-5 mr-2">
          <path stroke-linecap="round" stroke-linejoin="round"
                d="M10.5 1.5H8.25A2.25 2.25 0 0 0 6 3.75v16.5a2.25 2.25 0 0 0 2.25 2.25h7.5A2.25 2.25 0 0 0 18 20.25V3.75a2.25 2.25 0 0 0-2.25-2.25H13.5m-3 0V3h3V1.5m-3 0h3m-3 18.75h3"/>
        </svg>
        <span class="font-semibold">${signText}</span>
      `
    }
  }

  redirectToEidentitaUrl(eidentitaUrl) {
    const inIframe = window.self !== window.top

    if (inIframe) {
      try {
        window.top.location.href = eidentitaUrl
        console.log("Redirected via window.top (iframe detected)")
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
    } else {
      window.location.href = eidentitaUrl
      console.log("Redirected via window.location (not in iframe)")
    }
  }
}
