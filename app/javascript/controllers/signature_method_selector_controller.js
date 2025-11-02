import { Controller } from "@hotwired/stimulus"
import { isMobileDevice } from "utils/device_detection"

export default class extends Controller {
  static targets = ["methodRadio", "buttonContainer", "autogramForm", "avmForm", "signButton", "desktopElement"]

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
      if (this.hasAvmFormTarget) {
        const submitButton = this.avmFormTarget.querySelector('button[type="submit"]')
        if (submitButton) {
          submitButton.click()
        }
      }
    }
  }

  getSelectedMethod() {
    const selectedRadio = this.methodRadioTargets.find(radio => radio.checked)
    return selectedRadio ? selectedRadio.value : null
  }
}