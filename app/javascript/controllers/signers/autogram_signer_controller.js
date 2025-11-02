import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "submitButton"]
  static values = { 
    contractParam: String,
    contractUuid: String,
    noPreview: Boolean
  }

  connect() {
    this.signing = false
  }

  async sign(event) {
    if (this.signing) return
    
    event.preventDefault()
    this.signing = true
    
    // Show the signing in progress UI
    await this.showSigningInProgress()
    
    this.dispatchSigningEvent('start')

    try {
      if (typeof window.AutogramSDK === 'undefined') {
        throw new Error('An error occurred while loading the Autogram SDK. Please ensure it is properly included in the page.')
      }

      let client
      if (window.AutogramSDK.CombinedClient) {
        console.log('Using CombinedClient')
        client = await window.AutogramSDK.CombinedClient.init()
      } else {
        throw new Error('No suitable Autogram client found. Available properties: ' + Object.keys(window.AutogramSDK).join(', '))
      }

      const autogramParametersResponse = await fetch(this.contractParamValue + '/autogram_parameters', {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
        }
      })
      
      if (!autogramParametersResponse.ok) {
        throw new Error('Failed to load contract data from server.')
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

      const signResult = await client.signOnDesktop(
        signRequestDocument,
        signRequestSignatureParameters,
        autogramParameters.documents[0].content_type
      );

      if (signResult && signResult.content) {
        const formData = new FormData(this.formTarget)
        formData.append('signed_document', signResult.content)
        formData.append('signed_by', signResult.signedBy || '')
        formData.append('issued_by', signResult.issuedBy || '')
        
        const response = await fetch(this.formTarget.action, {
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
          window.parent.postMessage({ type: 'message', status: 'document-signed' }, '*');
          console.log('Document signed and submitted successfully, reloading page.')
          window.location.reload()
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
      console.error('Signing error:', error)
      
      if (error.message && (error.message.includes('cancel') || error.message.includes('abort'))) {
        console.log('User cancelled signing')
        this.dispatchSigningEvent('cancel')
      } else {
        alert(`An error occurred while signing: ${error.message}`)
        this.dispatchSigningEvent('error', { error: error.message })
      }
    }
  }

  dispatchSigningEvent(status, detail = {}) {
    const event = new CustomEvent('autogram-signing', {
      bubbles: true,
      detail: { status, ...detail }
    })
    this.element.dispatchEvent(event)
  }

  async showSigningInProgress() {
    try {
      let url = `${this.contractParamValue}/autogram_signing_in_progress`
      if (this.hasNoPreviewValue && this.noPreviewValue) {
        url += '?no_preview=1'
      }

      const response = await fetch(url, {
        headers: {
          'Accept': 'text/vnd.turbo-stream.html',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
        }
      })

      if (response.ok) {
        const turboStream = await response.text()
        Turbo.renderStreamMessage(turboStream)
      } else {
        console.error('Failed to load signing in progress view')
      }
    } catch (error) {
      console.error('Error showing signing in progress:', error)
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
      reader.onerror = () => reject(new Error('Failed to read file'));
      reader.readAsDataURL(blob);
    });
  }
}
