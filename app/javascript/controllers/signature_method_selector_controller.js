import { Controller } from "@hotwired/stimulus"
import { isMobileDevice } from "utils/device_detection"
import i18n from "i18n"

export default class extends Controller {
  static targets = ["methodRadio", "buttonContainer", "autogramForm", "avmForm", "eidentitaForm", "signButton", "desktopElement"]

  connect() {
    console.log('Signature method selector connected')
    this.handleDeviceDetection()
    this.element.addEventListener('autogram-signing', this.handleSigningEvent.bind(this))
  }

  disconnect() {
    this.element.removeEventListener('autogram-signing', this.handleSigningEvent.bind(this))
  }

  handleSigningEvent(event) {
    const { status } = event.detail
    console.log('Autogram signing event:', status)
    
    if (status === 'cancel' || status === 'error') {
      // Reload the page to restore the original form
      window.location.reload()
    }
    // Note: on success, the page reloads so no need to reset
  }

  handleDeviceDetection() {
    if (isMobileDevice()) {
      this.desktopElementTargets.forEach(element => {
        element.style.display = 'none'
      })

      const autogramRadio = this.methodRadioTargets.find(radio => radio.value === 'autogram')
      const avmRadio = this.methodRadioTargets.find(radio => radio.value === 'avm')
      
      if (autogramRadio && autogramRadio.checked && avmRadio) {
        autogramRadio.checked = false
        avmRadio.checked = true
      }
    } else {
      this.desktopElementTargets.forEach(element => {
        element.style.display = 'block'
      })
    }
  }

  triggerSign(event) {
    event.preventDefault()

    const selectedMethod = this.getSelectedMethod()
    console.log('Selected signing method:', selectedMethod)

    if (selectedMethod === 'autogram') {
      if (isMobileDevice()) {
        alert('Autogram Desktop is not available on mobile devices. Please use AVM Mobile instead.')
        return
      }

      // Trigger the autogram form submission
      // The autogram signer controller will handle showing the "signing in progress" UI
      if (this.hasAutogramFormTarget) {
        const submitButton = this.autogramFormTarget.querySelector('button[type="submit"]')
        if (submitButton) {
          submitButton.click()
        }
      }
    } else if (selectedMethod === 'avm') {
      // Show loading state on the main Sign button
      this.setSignButtonLoading(true)
      
      if (this.hasAvmFormTarget) {
        const submitButton = this.avmFormTarget.querySelector('button[type="submit"]')
        if (submitButton) {
          submitButton.click()
        }
      }
    } else if (selectedMethod === 'eidentita') {
      // Show loading state on the main Sign button
      this.setSignButtonLoading(true)
      
      if (this.hasEidentitaFormTarget) {
        const submitButton = this.eidentitaFormTarget.querySelector('button[type="submit"]')
        if (submitButton) {
          submitButton.click()
        }
      }
    }
  }

  setSignButtonLoading(loading) {
    if (!this.hasSignButtonTarget) return

    const button = this.signButtonTarget
    if (loading) {
      button.disabled = true
      const preparingText = i18n.t('signature.preparing')
      button.innerHTML = `
        <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-white inline" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        <span>${preparingText}</span>
      `
    } else {
      button.disabled = false
      button.innerHTML = i18n.t('signature.sign')
    }
  }

  getSelectedMethod() {
    const selectedRadio = this.methodRadioTargets.find(radio => radio.checked)
    return selectedRadio ? selectedRadio.value : null
  }
}