import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["methodRadio", "continueButton"]
  static values = {
    contractId: String,
    recipientUuid: String,
    bundleId: String,
    electronicOnboarding: Boolean,
    physicalOnboarding: Boolean
  }

  connect() {
    console.log('Signing method controller connected')
  }

  handleMethodSelection(event) {
    // Just enable the continue button when a method is selected
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

    // Check if onboarding is required for the selected method
    const onboardingRequired = selectedMethod === 'electronic' 
      ? this.electronicOnboardingValue 
      : this.physicalOnboardingValue

    if (onboardingRequired) {
      // Redirect to onboarding
      this.redirectToOnboarding(selectedMethod)
    } else {
      // Skip onboarding and go directly to the appropriate action page
      this.redirectToAction(selectedMethod)
    }
  }

  getSelectedMethod() {
    const selectedRadio = this.methodRadioTargets.find(radio => radio.checked)
    return selectedRadio ? selectedRadio.value : null
  }

  redirectToOnboarding(method) {
    const firstStep = method === 'electronic' ? 'eid_card_generation' : 'physical_instructions'
    let url = `/contracts/${this.contractIdValue}/onboarding/${firstStep}?method=${method}`
    
    if (this.recipientUuidValue) {
      url += `&recipient=${this.recipientUuidValue}`
    }
    
    if (this.bundleIdValue) {
      url += `&bundle_id=${this.bundleIdValue}`
    }
    
    window.location.href = url
  }

  redirectToAction(method) {
    if (method === 'electronic') {
      let url = `/contracts/${this.contractIdValue}/signature_apps`
      const params = []
      
      if (this.recipientUuidValue) {
        params.push(`recipient=${this.recipientUuidValue}`)
      }
      
      if (this.bundleIdValue) {
        params.push(`bundle_id=${this.bundleIdValue}`)
      }
      
      if (params.length > 0) {
        url += `?${params.join('&')}`
      }
      
      window.location.href = url
    } else {
      let url = `/contracts/${this.contractIdValue}/physical_signing`
      const params = []
      
      if (this.recipientUuidValue) {
        params.push(`recipient=${this.recipientUuidValue}`)
      }
      
      if (this.bundleIdValue) {
        params.push(`bundle_id=${this.bundleIdValue}`)
      }
      
      if (params.length > 0) {
        url += `?${params.join('&')}`
      }
      
      window.location.href = url
    }
  }
}
