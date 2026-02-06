import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["methodRadio", "continueButton", "electronicButton", "physicalButton"]

  connect() {
    console.log('Signing method controller connected')
  }

  handleMethodSelection(event) {
    this.continueButtonTarget.disabled = false
  }

  continue(event) {
    event.preventDefault()
    
    const selectedMethod = this.getSelectedMethod()
    console.log('Selected signing method:', selectedMethod)

    if (!selectedMethod) {
      alert('Please select a signing method')
      return
    }

    if (selectedMethod === 'electronic') {
      if (this.hasElectronicButtonTarget) {
        this.electronicButtonTarget.click()
      }
    } else if (selectedMethod === 'physical') {
      if (this.hasPhysicalButtonTarget) {
        this.physicalButtonTarget.click()
      }
    }
  }

  getSelectedMethod() {
    const selectedRadio = this.methodRadioTargets.find(radio => radio.checked)
    return selectedRadio ? selectedRadio.value : null
  }
}
