import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["methodRadio", "buttonContainer", "signerController", "autogramForm", "avmForm", "signButton"]

  connect() {
    console.log('Signature method selector connected')
  }

  triggerSign(event) {
    event.preventDefault()
    
    const selectedMethod = this.getSelectedMethod()
    console.log('Selected signing method:', selectedMethod)
    
    if (selectedMethod === 'autogram') {
      // Check if desktop/mobile and show appropriate UI
      const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent) || 
                      ('ontouchstart' in window) || 
                      (navigator.maxTouchPoints > 0)
      
      if (isMobile) {
        alert('Autogram Desktop is not available on mobile devices. Please use AVM Mobile instead.')
        return
      }
      
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