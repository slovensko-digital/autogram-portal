import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["methodRadio", "buttonContainer", "signerController"]

  connect() {
    // Use a small delay to ensure DOM is fully ready
    setTimeout(() => {
      this.updateButtons()
    }, 10)
  }

  updateButtons() {
    const selectedMethod = this.getSelectedMethod()
    const buttons = this.buttonContainerTarget.querySelectorAll('button[type="submit"]')
    const signerControllers = this.signerControllerTargets
    
    console.log('Selected method:', selectedMethod) // Debug log
    
    // Enable/disable buttons based on method selection
    if (selectedMethod) {
      buttons.forEach(button => {
        button.disabled = false
      })
      
      // Update timestamp data attribute on document signer controllers
      const useTimestamp = selectedMethod === 'ts-qes'
      signerControllers.forEach(signerElement => {
        signerElement.setAttribute('data-document-signer-use-timestamp-value', useTimestamp)
        // Notify the document signer controller about the change
        const controller = this.application.getControllerForElementAndIdentifier(signerElement, 'document-signer')
        if (controller && controller.useTimestampValueChanged) {
          controller.useTimestampValueChanged()
        }
      })
      
      console.log('Buttons enabled, timestamp:', useTimestamp) // Debug log
    } else {
      buttons.forEach(button => {
        button.disabled = true
      })
      console.log('No method selected, buttons disabled') // Debug log
    }
  }

  getSelectedMethod() {
    const selectedRadio = this.methodRadioTargets.find(radio => radio.checked)
    return selectedRadio ? selectedRadio.value : null
  }
}