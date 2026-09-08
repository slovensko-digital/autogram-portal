import { Controller } from "@hotwired/stimulus"
import { isMobileDevice } from "utils/device_detection"
import i18n from "i18n"

export default class extends Controller {
  static targets = ["appRadio", "autogramSubmitButton", "avmSubmitButton", "eidentitaSubmitButton", "podpisujSubmitButton", "signButton", "mobileWarning", "yellowWarning", "appSelectionHeading"]

  connect() {
    console.log('Signing app selector connected')
    this.handleDeviceDetection()
  }

  handleSigningEvent(event) {
    const { status } = event.detail
    console.log('Autogram signing event:', status)

    if (status === 'cancel' || status === 'error') {
      window.location.reload()
    }
  }

  handleDeviceDetection() {
    const mobileDevice = isMobileDevice()
    if (mobileDevice) {
      this.appRadioTargets
        .filter(radio => radio.dataset.desktopOnly === 'true')
        .forEach(radio => this.disableForDevice(radio))
    }

    const enabledRadios = this.appRadioTargets.filter(radio => !radio.disabled)
    if (!enabledRadios.some(radio => radio.checked) && enabledRadios.length > 0) {
      enabledRadios[0].checked = true
    }

    if (enabledRadios.length === 0) {
      if (mobileDevice) {
        if (this.hasMobileWarningTarget) {
          this.mobileWarningTarget.style.display = 'block'
        }

        if (this.hasYellowWarningTarget) {
          this.yellowWarningTarget.style.display = 'none'
        }

        if (this.hasAppSelectionHeadingTarget) {
          this.appSelectionHeadingTarget.style.display = 'none'
        }
      }

      if (this.hasSignButtonTarget) {
        this.signButtonTarget.disabled = true
        this.signButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
      }
    }
  }

  disableForDevice(radio) {
    const card = radio.closest('label')
    if (!card) return

    radio.checked = false
    radio.disabled = true
    card.tabIndex = 0
    card.setAttribute('aria-disabled', 'true')
    card.classList.remove('bg-white', 'hover:border-blue-300', 'hover:bg-blue-50', 'cursor-pointer')
    card.classList.add('cursor-not-allowed', 'border-gray-200', 'bg-gray-50', 'text-gray-500', 'opacity-75')

    const reasonId = `${radio.id}_device_disabled_reason`
    if (document.getElementById(reasonId)) return

    const reason = document.createElement('div')
    reason.id = reasonId
    reason.className = 'mt-2 text-xs font-medium text-gray-600'
    reason.textContent = radio.dataset.desktopOnlyReason
    card.querySelector('.flex-1')?.appendChild(reason)

    const describedBy = [card.getAttribute('aria-describedby'), reasonId].filter(Boolean).join(' ')
    card.setAttribute('aria-describedby', describedBy)
  }

  triggerSign(event) {
    event.preventDefault()

    const selectedApp = this.getSelectedApp()
    console.log('Selected signing app:', selectedApp)

    if (selectedApp === 'autogram') {
      if (this.hasAutogramSubmitButtonTarget) {
        this.setSignButtonLoading(true)
        this.autogramSubmitButtonTarget.click()
      }
    } else if (selectedApp === 'avm') {
      if (this.hasAvmSubmitButtonTarget) {
        this.setSignButtonLoading(true)
        this.avmSubmitButtonTarget.click()
      }
    } else if (selectedApp === 'eidentita') {
      if (this.hasEidentitaSubmitButtonTarget) {
        this.setSignButtonLoading(true)
        this.eidentitaSubmitButtonTarget.click()
      }
    } else if (selectedApp === 'podpisuj') {
      if (this.hasPodpisujSubmitButtonTarget) {
        this.setSignButtonLoading(true)
        this.podpisujSubmitButtonTarget.click()
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

  getSelectedApp() {
    const selectedRadio = this.appRadioTargets.find(radio => radio.checked && !radio.disabled)
    return selectedRadio ? selectedRadio.value : null
  }
}