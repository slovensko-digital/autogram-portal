import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["methodRadio", "buttonContainer", "signerController"]

  connect() {
    setTimeout(() => {
      this.updateButtons()
    }, 10)
  }

  updateButtons() {
    const selectedMethod = this.getSelectedMethod()
    const buttons = this.buttonContainerTarget.querySelectorAll('button[type="submit"]')
    const signerControllers = this.signerControllerTargets
    
    if (selectedMethod) {
      buttons.forEach(button => {
        button.disabled = false
      })
      
      const useTimestamp = selectedMethod === 'ts-qes'
      signerControllers.forEach(signerElement => {
        signerElement.setAttribute('data-document-signer-use-timestamp-value', useTimestamp)
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