import { Controller } from "@hotwired/stimulus"
import { isMobileDevice } from "utils/device_detection"

export default class extends Controller {
  static targets = ["submitButton"]

  connect() {
    console.log("AVM signer controller connected")
  }

  sign(event) {
    if (isMobileDevice()) {
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
        const avmUrl = this.extractAvmUrlFromResponse(responseText)
        if (avmUrl) {
          console.log("Redirecting to AVM URL:", avmUrl)
          this.redirectToAvmUrl(avmUrl)
        } else {
          console.log("Could not extract AVM URL, falling back to normal flow")
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

  extractAvmUrlFromResponse(responseText) {
    const matches = responseText.match(/href="(https:\/\/autogram\.slovensko\.digital\/api\/v1\/qr-code\?[^"]+)"/g)
    if (matches && matches.length > 0) {
      let url = matches[0]
      if (url.includes('="')) {
        url = url.split('"')[1]
      }
      if (url.startsWith('https://')) {
        url = this.decodeHtmlEntities(url)
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