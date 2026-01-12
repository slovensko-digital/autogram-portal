import { Controller } from "@hotwired/stimulus"
import { isMobileDevice } from "utils/device_detection"

export default class extends Controller {
  static targets = ["submitButton"]

  connect() {
    console.log("AVM signer controller connected")
  }

  sign(event) {
    this.setButtonLoading(true)
    if (isMobileDevice()) {
      event.preventDefault()
      this.submitAndRedirect()
    }
  }

  async submitAndRedirect() {
    try {
      const form = this.element
      const formData = new FormData(form)
      
      const response = await fetch(form.action, {
        method: form.method,
        body: formData,
        headers: {
          'Accept': 'text/vnd.turbo-stream.html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (response.ok) {
          const responseText = await response.text()
          console.log("Response: ", responseText);
        
        const avmUrl = this.extractAvmUrlFromResponse(responseText)
        
        if (avmUrl) {
          console.log("Redirecting to AVM URL:", avmUrl)
          this.redirectToAvmUrl(avmUrl)
        } else {
          console.log("Could not extract AVM URL, falling back to normal flow")
          this.processTurboStreamResponse(responseText)
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
    const patterns = [
      /https:\/\/autogram\.slovensko\.digital\/api\/v1\/qr-code\?[^"'\s>]+/g,
      /data-avm-url="([^"]+)"/g,
      /href="(https:\/\/autogram\.slovensko\.digital\/api\/v1\/qr-code\?[^"]+)"/g
    ]
    
    for (const pattern of patterns) {
      const matches = responseText.match(pattern)
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
    }
    
    return null
  }

  decodeHtmlEntities(text) {
    const tempElement = document.createElement('div')
    tempElement.innerHTML = text
    return tempElement.textContent || tempElement.innerText || text
  }

  processTurboStreamResponse(responseText) {
    const tempDiv = document.createElement('div')
    tempDiv.innerHTML = responseText
    const turboStreamElement = tempDiv.querySelector('turbo-stream')
    
    if (turboStreamElement) {
      document.body.appendChild(turboStreamElement)
      setTimeout(() => {
        if (turboStreamElement.parentNode) {
          turboStreamElement.parentNode.removeChild(turboStreamElement)
        }
      }, 100)
    }
    
    this.setButtonLoading(false)
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
      button.innerHTML = `
        <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        <span class="font-semibold">Opening AVM...</span>
      `
    } else {
      button.disabled = false
      button.innerHTML = `
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5"
              stroke="currentColor" class="w-5 h-5 mr-2">
          <path stroke-linecap="round" stroke-linejoin="round"
                d="M3.75 4.875c0-.621.504-1.125 1.125-1.125h4.5c.621 0 1.125.504 1.125 1.125v4.5c0 .621-.504 1.125-1.125 1.125h-4.5A1.125 1.125 0 0 1 3.75 9.375v-4.5ZM3.75 14.625c0-.621.504-1.125 1.125-1.125h4.5c.621 0 1.125.504 1.125 1.125v4.5c0 .621-.504 1.125-1.125 1.125h-4.5a1.125 1.125 0 0 1-1.125-1.125v-4.5ZM13.5 4.875c0-.621.504-1.125 1.125-1.125h4.5c.621 0 1.125.504 1.125 1.125v4.5c0 .621-.504 1.125-1.125 1.125h-4.5A1.125 1.125 0 0 1 13.5 9.375v-4.5Z"/>
          <path stroke-linecap="round" stroke-linejoin="round" d="M6.75 6.75h.75v.75h-.75v-.75ZM6.75 16.5h.75v.75h-.75v-.75ZM16.5 6.75h.75v.75h-.75v-.75ZM13.5 13.5h4.5v4.5h-4.5v-4.5Z"/>
        </svg>
        <span class="font-semibold">Sign with AVM</span>
      `
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