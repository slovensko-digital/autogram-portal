import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]

  connect() {
    console.log("AVM signer controller connected")
  }

  handleClick(event) {
    // Check if we're on a mobile device
    if (this.isMobileDevice()) {
      console.log("Mobile device detected, handling AVM signing directly")
      
      // Prevent the default form submission
      event.preventDefault()
      
      // Show loading state
      this.setButtonLoading(true)
      
      // Submit the form to get the AVM URL, then redirect directly
      this.submitAndRedirect()
    }
    // On desktop, let the form submit normally to show QR code
  }

  async submitAndRedirect() {
    try {
      const form = this.element
      const formData = new FormData(form)
      
      // Submit the form using fetch
      const response = await fetch(form.action, {
        method: form.method,
        body: formData,
        headers: {
          'Accept': 'text/vnd.turbo-stream.html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (response.ok) {
          // Get the turbo stream response
          const responseText = await response.text()
          console.log("Response: ", responseText);
        
        // Extract the AVM URL from the response
        const avmUrl = this.extractAvmUrlFromResponse(responseText)
        
        if (avmUrl) {
          console.log("Redirecting to AVM URL:", avmUrl)
          // Open the AVM URL directly - this should trigger the mobile app
          window.location.href = avmUrl
        } else {
          console.log("Could not extract AVM URL, falling back to normal flow")
          // If we can't extract the URL, process the turbo stream normally
          this.processTurboStreamResponse(responseText)
        }
      } else {
        console.error("Form submission failed:", response.status, response.statusText)
        this.showError("Failed to initiate signing. Please try again.")
      }
    } catch (error) {
      console.error("Error submitting form:", error)
      this.showError("Network error occurred. Please check your connection and try again.")
    }
  }

  extractAvmUrlFromResponse(responseText) {
    // Look for the AVM URL in the turbo stream response
    // The URL should be in the format: https://autogram.slovensko.digital/api/v1/qr-code?guid=...&key=...
    const patterns = [
      /https:\/\/autogram\.slovensko\.digital\/api\/v1\/qr-code\?[^"'\s>]+/g,
      /data-avm-url="([^"]+)"/g,
      /href="(https:\/\/autogram\.slovensko\.digital\/api\/v1\/qr-code\?[^"]+)"/g
    ]
    
    for (const pattern of patterns) {
      const matches = responseText.match(pattern)
      if (matches && matches.length > 0) {
        // Extract URL from the match (handle both direct matches and attribute matches)
        let url = matches[0]
        if (url.includes('="')) {
          url = url.split('"')[1]
        }
        if (url.startsWith('https://')) {
          // Decode HTML entities (especially &amp; to &)
          url = this.decodeHtmlEntities(url)
          return url
        }
      }
    }
    
    return null
  }

  decodeHtmlEntities(text) {
    // Create a temporary DOM element to decode HTML entities
    const tempElement = document.createElement('div')
    tempElement.innerHTML = text
    return tempElement.textContent || tempElement.innerText || text
  }

  processTurboStreamResponse(responseText) {
    // Process the turbo stream response normally
    // This will show the QR code interface
    const tempDiv = document.createElement('div')
    tempDiv.innerHTML = responseText
    const turboStreamElement = tempDiv.querySelector('turbo-stream')
    
    if (turboStreamElement) {
      // Let Turbo handle the stream
      document.body.appendChild(turboStreamElement)
      // Clean up
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
    // You could implement a toast notification here or use the existing error handling
    alert(message)
  }

  setButtonLoading(loading) {
    const button = this.buttonTarget
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

  isMobileDevice() {
    // Check for mobile device using multiple methods
    const userAgent = navigator.userAgent || navigator.vendor || window.opera

    // Method 1: User agent detection
    const mobileRegex = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
    const isMobileUA = mobileRegex.test(userAgent)

    // Method 2: Touch capability and screen size
    const isTouchDevice = 'ontouchstart' in window || navigator.maxTouchPoints > 0
    const isSmallScreen = window.innerWidth <= 768

    // Method 3: Check for mobile-specific features
    const hasMobileFeatures = 'orientation' in window || 'DeviceMotionEvent' in window

    // Consider it mobile if it matches user agent OR (has touch + small screen + mobile features)
    return isMobileUA || (isTouchDevice && isSmallScreen && hasMobileFeatures)
  }
}