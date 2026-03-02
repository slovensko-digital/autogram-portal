import { Controller } from "@hotwired/stimulus"
import i18n from "i18n"

export default class extends Controller {
  static targets = ["form", "progressBar", "progressPercent", "statusChecking", "statusStarting", "statusSending", "statusWaiting", "statusSigned", "stateNormal", "stateNotInstalled", "stateCancelled", "stateError", "errorMessage"]
  static values = {
    autogramParametersPath: String,
    signedDocumentPath: String,
    sdkPath: String
  }

  connect() {
    console.log('Autogram signer controller connected')
    this.loadSDKScript().then(() => {
      this.sign()
    })
  }

  loadSDKScript() {
    return new Promise((resolve) => {
      if (typeof window.AutogramSDK !== 'undefined') {
        resolve()
        return
      }

      const existingScript = document.querySelector('script[src*="autogram-sdk"]')
      if (existingScript) {
        existingScript.addEventListener('load', () => resolve())
        existingScript.addEventListener('error', () => resolve())
        return
      }

      const script = document.createElement('script')
      script.src = this.sdkPathValue
      script.async = true
      script.addEventListener('load', () => resolve())
      script.addEventListener('error', () => resolve())
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

  async sign() {
    console.log('Starting Autogram Desktop signing process')

    try {
      await this.waitForSDK()

      if (typeof window.AutogramSDK === 'undefined') {
        throw new Error('An error occurred while loading the Autogram SDK. Please ensure it is properly included in the page.')
      }

      let client
      if (window.AutogramSDK.DesktopClient) {
        console.log('Using DesktopClient')
        client = new window.AutogramSDK.DesktopClient()
      } else {
        throw new Error('No suitable Autogram client found. Available properties: ' + Object.keys(window.AutogramSDK).join(', '))
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

      for (let doc of autogramParameters.documents) {
        doc.contentPromise = Promise.resolve(doc.content);

        if (doc.download_url) {
          doc.contentPromise = fetch(doc.download_url)
            .then(response => {
              if (!response.ok) {
                throw new Error('Network response was not ok');
              }
              return response.blob();
            });
        }
      }

      for (let doc of autogramParameters.documents) {
        let content = await doc.contentPromise;

        if (doc.content_type.includes('base64')) {
          doc.content = content
        } else {
          doc.content = await this.blobToBase64(content);
          doc.content_type += ';base64';
        }
      }

      let signRequestDocument = {
        content: autogramParameters.documents[0].content
      }

      if (autogramParameters.documents[0].filename)
        signRequestDocument.filename = autogramParameters.documents[0].filename;

      let signRequestSignatureParameters = this.getOldSignatureParameters(
        autogramParameters.signature_parameters,
        autogramParameters.documents[0].xdc_parameters
      );

      console.log('Signing document with parameters:', signRequestDocument, signRequestSignatureParameters, autogramParameters.documents[0].content_type)

      let signResult = await client.sign(
        signRequestDocument,
        signRequestSignatureParameters,
        autogramParameters.documents[0].content_type,
        {
          onStateChange: (state) => {
            if (state.type === 'checkingApp') {
              this.updateProgress(0, 'checking')
            }
            if (state.type === 'launchingApp') {
              this.updateProgress(25, 'starting')
            }
            if (state.type === 'waitingForSignature') {
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
          }
        }
      )

      this.updateProgress(100, 'signed')

      if (signResult && signResult.content) {
        const formData = new FormData()
        formData.append('signed_document', signResult.content)
        formData.append('signed_by', signResult.signedBy || '')
        formData.append('issued_by', signResult.issuedBy || '')

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
          
          window.parent.postMessage({ type: 'message', status: 'document-signed' }, '*');
          console.log('Document signed and submitted successfully. Turbo stream refresh will redirect to sign page.')
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
      if (error.message && (error.message.includes('cancel') || error.message.includes('abort'))) {
        console.log('User cancelled signing - already handled by onStateChange callback')
        return
      }
      
      // Check if already handled by onStateChange (appNotInstalled, error states)
      if (error.message && (error.message.includes('error') || error.message.includes('nainštalovaný') || error.message.includes('installed'))) {
        console.log('Error already handled by onStateChange callback')
        return
      }
      
      // Only show inline error for unexpected errors not caught by SDK
      console.error('Unexpected signing error:', error)
      this.showErrorState(error.message)
    }
  }

  getOldSignatureParameters(newParams, xdcParams) {
    let result = {
      level: newParams.format + "_" + newParams.level,
      container: newParams.container
    };

    console.log('xdc params:', xdcParams)
    if (xdcParams) {
      console.log('Using XDC parameters:', xdcParams)
      result.autoLoadEform = xdcParams.auto_load_eform;
      result.containerXmlns = xdcParams.container_xmlns;
      result.embedUsedSchemas = xdcParams.embed_used_schemas;
      result.identifier = xdcParams.identifier;
      result.fsFormId = xdcParams.fs_form_identifier;
      result.packaging = xdcParams.packaging;
      result.schemaIdentifier = xdcParams.schema_identifier;
      result.transformationIdentifier = xdcParams.transformation_identifier;

      if (xdcParams.schema != null) {
        if (xdcParams.schema_mime_type && xdcParams.schema_mime_type.includes('base64')) {
          result.schema = xdcParams.schema;
          result.transformation = xdcParams.transformation;
        } else {
          result.schema = this.stringToBase64(xdcParams.schema);
          result.schemaMimeType = xdcParams.schema_mime_type + ';base64';
          result.transformation = this.stringToBase64(xdcParams.transformation);
          result.transformationMimeType = xdcParams.transformation_mime_type + ';base64';
        }
      }
    } else {
      console.log('No XDC parameters found, using defaults')
      result.autoLoadEform = true;
    }

    console.log('Final signature parameters:', result)
    return result;
  }

  stringToBase64(bytes) {
    let file = new File([bytes], "file");
    return this.blobToBase64(file);
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
          this.resetStatus(this.statusCheckingTarget)
          this.resetStatus(this.statusStartingTarget)
          this.markFailed(this.statusWaitingTarget)
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
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor" class="w-4 h-4 text-white">
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
        <svg class="animate-spin h-6 w-6 text-blue-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
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
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor" class="w-4 h-4 text-white">
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
    if (this.hasStateNotInstalledTarget) this.stateNotInstalledTarget.classList.add('hidden')
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
