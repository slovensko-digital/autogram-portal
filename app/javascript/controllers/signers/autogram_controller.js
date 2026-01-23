import { Controller } from "@hotwired/stimulus"
import i18n from "i18n"

export default class extends Controller {
  static targets = ["form"]
  static values = { 
    autogramParametersPath: String,
    signedDocumentPath: String,
    sdkPath: String
  }

  connect() {
    console.log('Autogram signer controller connected')
    this.loadSDKScript()
  }

  loadSDKScript() {
    if (typeof window.AutogramSDK !== 'undefined' || document.querySelector('script[src*="autogram-sdk"]')) {
      return
    }

    const script = document.createElement('script')
    script.src = this.sdkPathValue
    script.async = true
    document.head.appendChild(script)
    console.log('Loading Autogram SDK script from:', this.sdkPathValue)
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

  isInIframe() {
    try {
      return window.self !== window.top
    } catch (e) {
      return true
    }
  }

  createIframeCompatibleDesktopClient() {
    if (!window.AutogramSDK || !window.AutogramSDK.desktopApiClient) {
      return null
    }

    return window.AutogramSDK.desktopApiClient({
      serverProtocol: 'http',
      serverHost: 'localhost',
      disableSecurity: true,
      requestsOrigin: '*'
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
      const inIframe = this.isInIframe()

      if (inIframe) {
        client = this.createIframeCompatibleDesktopClient()
        if (!client) {
          throw new Error(i18n.t('errors.iframe_client_error'))
        }
      } else if (window.AutogramSDK.CombinedClient) {
        console.log('Using CombinedClient')
        client = await window.AutogramSDK.CombinedClient.init()
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

      let signResult

      if (inIframe) {
        signResult = await this.signWithDesktopClient(
          client,
          signRequestDocument,
          signRequestSignatureParameters,
          autogramParameters.documents[0].content_type
        )
      } else {
        signResult = await client.signOnDesktop(
          signRequestDocument,
          signRequestSignatureParameters,
          autogramParameters.documents[0].content_type
        )
      }

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
      if (error.message && (error.message.includes('cancel') || error.message.includes('abort'))) {
        console.log('User cancelled signing')
        window.location.reload()
      } else {
        console.error('Signing error:', error)
        alert(i18n.t('errors.signing_error', { message: error.message }))
        window.location.reload()
      }
    }
  }

  async showSigningInProgress() {
    try {
      const response =  await fetch(this.element.action, {
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

  async signWithDesktopClient(client, document, parameters, mimeType) {
    console.log('Signing with desktop client in iframe mode')

    try {
      const info = await client.info()
      console.log('Autogram Desktop is ready:', info)
    } catch (error) {
      console.log('Autogram Desktop not running, launching...')
      const launchUrl = await client.getLaunchURL('listen')
      console.log('Opening launch URL:', launchUrl)

      try {
        const opened = window.open(launchUrl, '_self')
        if (!opened) {
          const link = document.createElement ? document.createElement('a') : null
          if (link) {
            link.href = launchUrl
            link.style.display = 'none'
            document.body.appendChild(link)
            link.click()
            document.body.removeChild(link)
          }
        }
      } catch (e) {
        console.log('Could not open launch URL:', e)
        window.location.assign(launchUrl)
      }

      console.log('Waiting for Autogram Desktop to become ready...')
      try {
        await client.waitForStatus('READY', 60, 2)
        console.log('Autogram Desktop is now ready')
      } catch (waitError) {
        console.error('Timeout waiting for Autogram Desktop:', waitError)
        throw new Error(i18n.t('errors.autogram_connection_failed'))
      }
    }

    console.log('Sending sign request to Autogram Desktop')
    const result = await client.sign(document, parameters, mimeType)
    console.log('Sign result:', result)

    return result
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
}
