import { Controller } from "@hotwired/stimulus"
import i18n from "i18n"
import { documentToSign, signatureParameters } from "utils/autogram_sign_request"

export default class extends Controller {
  static targets = ["form", "progressBar", "progressPercent", "statusChecking", "statusStarting", "statusSending", "statusWaiting", "statusSigned", "stateNormal", "stateMaybeNotInstalled", "stateNotInstalled", "stateAppVersionTooLow", "stateCancelled", "stateError", "errorMessage"]
  static values = {
    autogramParametersPath: String,
    signedDocumentPath: String,
    sdkPath: String
  }

  connect() {
    console.log('Autogram signer controller connected')
    this.loadSDKScript().then(() => {
      this.sign()
    }).catch((error) => {
      console.error('Failed to load Autogram SDK script:', error)
      this.showErrorState(error?.message || 'Autogram SDK sa nepodarilo načítať')
    })
  }

  loadSDKScript() {
    return new Promise((resolve, reject) => {
      if (typeof window.AutogramSDK !== 'undefined') {
        resolve(window.AutogramSDK)
        return
      }

      if (!this.hasSdkPathValue || !this.sdkPathValue) {
        reject(new Error('Autogram SDK URL nie je nakonfigurovaná pre túto stránku.'))
        return
      }

      const existingScript = document.querySelector('script[src*="autogram-sdk"]')
      if (existingScript) {
        existingScript.addEventListener('load', () => resolve(window.AutogramSDK))
        existingScript.addEventListener('error', () => reject(new Error(`Autogram SDK sa nepodarilo načítať z ${this.sdkPathValue}.`)))
        return
      }

      const script = document.createElement('script')
      script.src = this.sdkPathValue
      script.async = true
      script.addEventListener('load', () => resolve(window.AutogramSDK))
      script.addEventListener('error', () => reject(new Error(`Autogram SDK sa nepodarilo načítať z ${this.sdkPathValue}.`)))
      document.head.appendChild(script)
      console.log('Loading Autogram SDK script from:', this.sdkPathValue)
    })
  }

  waitForSDK(maxWaitTime = 5000) {
    return new Promise((resolve, _) => {
      if (typeof window.AutogramSDK !== 'undefined') {
        resolve()
        return
      }

      const startTime = Date.now()
      const checkInterval = setInterval(() => {
        if (typeof window.AutogramSDK !== 'undefined') {
          clearInterval(checkInterval)
          resolve()
        } else if (Date.now() - startTime > maxWaitTime) {
          clearInterval(checkInterval)
          resolve()
        }
      }, 100)
    })
  }

  isUserCancelledError(sdk, error) {
    if (!error) {
      return false
    }

    if (typeof sdk.UserCancelledSigningException === 'function' && error instanceof sdk.UserCancelledSigningException) {
      return true
    }

    return error.name === 'UserCancelledSigningException' ||
      error.message?.includes('cancel') ||
      error.message?.includes('Aborted')
  }

  isAppNotInstalledError(sdk, error) {
    if (!error) {
      return false
    }

    if (typeof sdk.AutogramAppNotInstalledException === 'function' && error instanceof sdk.AutogramAppNotInstalledException) {
      return true
    }

    if (typeof sdk.AutogramAppVersionTooLowException === 'function' && error instanceof sdk.AutogramAppVersionTooLowException) {
      return false
    }

    return error.name === 'AutogramAppNotInstalledException'
  }

  isAppVersionTooLowError(sdk, error) {
    if (!error) {
      return false
    }

    if (typeof sdk.AutogramAppVersionTooLowException === 'function' && error instanceof sdk.AutogramAppVersionTooLowException) {
      return true
    }

    return error.name === 'AutogramAppVersionTooLowException'
  }

  async sign() {
    console.log('Starting Autogram Desktop signing process')

    let sdk = window.AutogramSDK || {}

    try {
      sdk = await this.loadSDKScript()

      if (typeof sdk === 'undefined' || typeof sdk.DesktopClient !== 'function') {
        throw new Error('An error occurred while loading the Autogram SDK. Please ensure it is properly included in the page.')
      }

      let client
      if (sdk.DesktopClient) {
        console.log('Using DesktopClient')
        client = new sdk.DesktopClient()
      } else {
        throw new Error('No suitable Autogram client found. Available properties: ' + Object.keys(sdk).join(', '))
      }

      const autogramParametersResponse = await fetch(this.autogramParametersPathValue, {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
        }
      })

      if (!autogramParametersResponse.ok) {
        throw new Error(i18n.t('errors.contract_load_failed'))
      }

      const autogramParameters = await autogramParametersResponse.json()

      const documents = await Promise.all(autogramParameters.documents.map(async (doc) => {
        return documentToSign(doc, await this.documentContent(doc))
      }))

      let states = {
        onStateChange: (state) => {
          if (state.type === 'checkingApp') {
            this.showNormalState()
            this.updateProgress(0, 'checking')
          }
          if (state.type === 'launchingApp') {
            this.showNormalState()
            this.updateProgress(25, 'starting')
          }
          if (state.type === 'appMayNotBeInstalled') {
            console.warn('Autogram may not be installed yet')
            this.showAppMayNotBeInstalledHint()
          }
          if (state.type === 'waitingForSignature') {
            this.showNormalState()
            this.updateProgress(75, 'waiting')
          }
          if (state.type === 'appNotInstalled') {
            console.error('Autogram is not installed')
            this.showAppNotInstalledMessage()
          }
          if (state.type === 'signingCancelled') {
            console.log('User cancelled signing')
            this.showCancelledState()
          }
          if (state.type === 'error') {
            console.error('Signing error:', state)
            this.showErrorState(state.message || 'Unknown error')
          }
          if (state.type === 'appVersionTooLow') {
            console.error('Autogram version is too low:', state)
            this.showAppVersionTooLowMessage();
          }
        }
      }

      // several documents are signed into one ASiC-E container, which needs Autogram 2.8.0 or newer:
      // with an older one the SDK reports the appVersionTooLow state and throws AutogramAppVersionTooLowException
      const signResult = await client.sign(
        documents,
        signatureParameters(autogramParameters.signature_parameters),
        states
      )

      this.updateProgress(100, 'signed')

      if (signResult && signResult.content) {
        const signature = signResult.signatures?.at(-1)
        const formData = new FormData()
        formData.append('signed_document', signResult.content)
        formData.append('signed_by', signature?.signedBy || '')
        formData.append('issued_by', signature?.issuedBy || '')

        const response = await fetch(this.signedDocumentPathValue, {
          method: 'POST',
          body: formData,
          headers: {
            'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content'),
            'Accept': 'application/json'
          }
        })

        if (response.redirected) {
          window.location.href = response.url
        } else if (response.ok) {
          this.updateProgress(100, 'signed')
          console.log('Document signed and submitted successfully. Turbo stream refresh will update the signing UI.')
        } else {
          const errorText = await response.text()
          let errorMessage = 'An error occurred while submitting the signed document.'

          try {
            const errorData = JSON.parse(errorText)
            errorMessage = errorData.error || errorMessage
          } catch {
          }

          throw new Error(errorMessage)
        }
      } else {
        console.log('Signing was cancelled or failed:', signResult)
      }
    } catch (error) {
      // Check if this is a user cancellation (already handled by onStateChange)
      if (this.isUserCancelledError(sdk, error)) {
        console.log('User cancelled signing - already handled by onStateChange callback')
        return
      }

      if (this.isAppNotInstalledError(sdk, error)) {
        console.log('App not installed - already handled by onStateChange callback')
        return
      }

      if (this.isAppVersionTooLowError(sdk, error)) {
        console.log('App version too low - already handled by onStateChange callback')
        return
      }

      // Only show inline error for unexpected errors not caught by SDK
      console.error('Unexpected signing error:', error)
      this.showErrorState(error?.message || 'Unknown error')
    }
  }

  async documentContent(doc) {
    if (!doc.download_url) {
      return doc.content
    }

    const response = await fetch(doc.download_url)
    if (!response.ok) {
      throw new Error('Network response was not ok')
    }

    return await this.blobToBase64(await response.blob())
  }

  blobToBase64(blob) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => {
        try {
          const result = reader.result;
          const base64Data = result.split('base64,')[1];
          resolve(base64Data);
        } catch (error) {
          reject(error);
        }
      };
      reader.onerror = () => reject(new Error(i18n.t('errors.file_read_failed')));
      reader.readAsDataURL(blob);
    });
  }

  updateProgress(percent, stage) {
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = `${percent}%`
    }
    if (this.hasProgressPercentTarget) {
      this.progressPercentTarget.textContent = `${percent}%`
    }

    if (this.hasStatusCheckingTarget && this.hasStatusStartingTarget && 
        this.hasStatusSendingTarget && this.hasStatusWaitingTarget && this.hasStatusSignedTarget) {
      
      switch(stage) {
        case 'starting':
          this.markActive(this.statusStartingTarget)
          break
        case 'waiting':
          this.markCompleted(this.statusCheckingTarget)
          this.markCompleted(this.statusStartingTarget)
          this.markCompleted(this.statusSendingTarget)
          this.markActive(this.statusWaitingTarget)
          break
        case 'signed':
          this.markCompleted(this.statusCheckingTarget)
          this.markCompleted(this.statusStartingTarget)
          this.markCompleted(this.statusSendingTarget)
          this.markCompleted(this.statusWaitingTarget)
          this.markCompleted(this.statusSignedTarget)
          break
        case 'notInstalled':
          this.markFailed(this.statusCheckingTarget)
          this.markFailed(this.statusStartingTarget)
          break
        case 'cancelled':
          this.markFailed(this.statusWaitingTarget)
          break
        case 'appVersionTooLow':
          this.markFailed(this.statusCheckingTarget)
          this.markFailed(this.statusStartingTarget)
          break
      }
    }
  }

  resetStatus(element) {
    element.classList.remove('bg-green-50', 'border-green-200')
    element.classList.remove('bg-white', 'border-blue-200')
    element.classList.add('bg-gray-100', 'border-gray-200', 'opacity-50')
    const icon = element.querySelector('.flex-shrink-0')
    if (icon) {
      icon.innerHTML = '<div style="width: 24px; height: 24px;" class="bg-gray-400 rounded-full"></div>'
    }
  }

  markCompleted(element) {
    element.classList.remove('bg-gray-100', 'border-gray-200', 'opacity-50')
    element.classList.remove('bg-white', 'border-blue-200')
    element.classList.add('bg-green-50', 'border-green-200')
    const icon = element.querySelector('.flex-shrink-0')
    if (icon) {
      icon.innerHTML = `
        <div style="width: 24px; height: 24px;" class="bg-green-600 rounded-full flex items-center justify-center">
          <svg aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor" class="w-4 h-4 text-white">
            <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" />
          </svg>
        </div>
      `
    }
  }

  markActive(element) {
    element.classList.remove('bg-gray-100', 'border-gray-200', 'opacity-50')
    element.classList.remove('bg-green-50', 'border-green-200')
    element.classList.remove('bg-blue-50')
    element.classList.add('bg-white', 'border-blue-200')
    const icon = element.querySelector('.flex-shrink-0')
    if (icon) {
      icon.innerHTML = `
        <svg aria-hidden="true" class="animate-spin h-6 w-6 text-blue-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
      `
    }
  }

  markFailed(element) {
    element.classList.remove('bg-gray-100', 'border-gray-200', 'opacity-50')
    element.classList.remove('bg-green-50', 'border-green-200')
    element.classList.remove('bg-white', 'border-blue-200')
    element.classList.remove('bg-blue-50')
    element.classList.add('bg-red-50', 'border-red-200')
    const icon = element.querySelector('.flex-shrink-0')
    if (icon) {
      icon.innerHTML = `
        <div style="width: 24px; height: 24px;" class="bg-red-600 rounded-full flex items-center justify-center">
          <svg aria-hidden="true" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor" class="w-4 h-4 text-white">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </div>
      `
    }
  }

  showAppNotInstalledMessage() {
    this.hideAllStates()
    this.updateProgress(25, 'notInstalled')
    if (this.hasStateNotInstalledTarget) {
      this.stateNotInstalledTarget.classList.remove('hidden')
    }
  }

  showAppVersionTooLowMessage() {
    this.hideAllStates()
    this.updateProgress(25, 'appVersionTooLow')
    if (this.hasStateAppVersionTooLowTarget) {
      this.stateAppVersionTooLowTarget.classList.remove('hidden')
    }
  }

  showAppMayNotBeInstalledHint() {
    this.hideAllStates()
    this.updateProgress(25, 'starting')
    if (this.hasStateMaybeNotInstalledTarget) {
      this.stateMaybeNotInstalledTarget.classList.remove('hidden')
    }
  }

  showNormalState() {
    this.hideAllStates()
    if (this.hasStateNormalTarget) {
      this.stateNormalTarget.classList.remove('hidden')
    }
  }

  showCancelledState() {
    this.updateProgress(75, 'cancelled')
    this.hideAllStates()
    if (this.hasStateCancelledTarget) {
      this.stateCancelledTarget.classList.remove('hidden')
    }
  }

  showErrorState(message) {
    this.hideAllStates()
    if (this.hasStateErrorTarget) {
      this.stateErrorTarget.classList.remove('hidden')
      if (this.hasErrorMessageTarget) {
        this.errorMessageTarget.textContent = `${message}. Presmerovávame vás späť...`
      }
    }
  }

  hideAllStates() {
    if (this.hasStateNormalTarget) this.stateNormalTarget.classList.add('hidden')
    if (this.hasStateMaybeNotInstalledTarget) this.stateMaybeNotInstalledTarget.classList.add('hidden')
    if (this.hasStateNotInstalledTarget) this.stateNotInstalledTarget.classList.add('hidden')
    if (this.hasStateAppVersionTooLowTarget) this.stateAppVersionTooLowTarget.classList.add('hidden')
    if (this.hasStateCancelledTarget) this.stateCancelledTarget.classList.add('hidden')
    if (this.hasStateErrorTarget) this.stateErrorTarget.classList.add('hidden')
  }

  showCancelledMessage() {
    // Deprecated - use showCancelledState instead
    this.showCancelledState()
  }

  showErrorMessage(message) {
    // Deprecated - use showErrorState instead  
    this.showErrorState(message)
  }

  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}
