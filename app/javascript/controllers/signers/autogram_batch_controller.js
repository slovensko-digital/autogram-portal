import { Controller } from "@hotwired/stimulus"
import i18n from "i18n"
import { isMobileDevice } from "utils/device_detection"

export default class extends Controller {
  static targets = ["progressBar", "progressPercent", "progressText", "currentDocumentName", "documentItem", "statusChecking", "statusStarting", "statusSending", "statusWaiting", "statusSigned", "stateNormal", "stateAppNotRunning", "stateSuccess", "stateCancelled", "stateError", "errorMessage"]

  static values = {
    items: String,
    returnPath: String,
    bundleId: String,
    totalContractsCount: Number,
    iframe: Boolean,
    sdkPath: String
  }

  connect() {
    this.abortController = new AbortController()
    this.isSigning = false
    this.currentStatusStage = "checking"

    this.updateProgress(0, this.items.length)
    this.currentDocumentNameTarget.textContent = ""
    this.setStatusStage("checking")
    this.signAll()
  }

  disconnect() {
    this.abortController?.abort()
  }

  get items() {
    return JSON.parse(this.itemsValue || "[]")
  }

  async signAll() {
    if (this.isSigning) {
      return
    }

    this.isSigning = true
    let sdk = null
    let client = null
    let batchId = null

    try {
      if (isMobileDevice()) {
        throw new Error(i18n.t("bundles.autogram_batch.desktop_only"))
      }

      if (this.items.length < 2) {
        throw new Error(i18n.t("bundles.sign.batch_sign_unavailable"))
      }

      sdk = await this.loadSDKScript()
      client = this.buildDesktopClient(sdk)
      batchId = await client.startBatch(this.items.length, {
        abortController: this.abortController,
        onStateChange: (state) => this.handleDesktopState(state)
      })

      this.setStatusStage("waiting")
      this.updateProgress(0, this.items.length)

      for (const [index, item] of this.items.entries()) {
        this.setStatusStage("waiting")
        this.updateProgress(index, this.items.length, item.contract_name)
        this.setDocumentItemStates(index)

        const autogramParameters = await this.loadAutogramParameters(item.parameters_path)
        const signRequest = await this.prepareSigningRequestBody(autogramParameters)
        const signedDocument = await client.sign(
          signRequest.document,
          signRequest.parameters,
          signRequest.payloadMimeType,
          {
            abortController: this.abortController,
            batchId: batchId
          }
        )
        await this.uploadSignedDocument(item.upload_path, signedDocument.content)

        this.updateProgress(index + 1, this.items.length, item.contract_name)
      }

      await client.endBatch(batchId, this.abortController)
      this.handleSuccess()
    } catch (error) {
      if (batchId && client) {
        try {
          await client.endBatch(batchId, this.abortController)
        } catch {
        }
      }

      if (
        this.isAbortError(error) ||
        this.isAppNotInstalledError(sdk, error) ||
        this.isUserCancelledError(sdk, error)
      ) {
        return
      }

      this.showErrorState(error?.message || i18n.t("bundles.autogram_batch.error_message"))
    } finally {
      this.isSigning = false
    }
  }

  loadSDKScript() {
    return new Promise((resolve, reject) => {
      if (typeof window.AutogramSDK !== "undefined") {
        resolve(window.AutogramSDK)
        return
      }

      if (!this.hasSdkPathValue || !this.sdkPathValue) {
        reject(new Error("Autogram SDK URL nie je nakonfigurovaná pre túto stránku."))
        return
      }

      const existingScript = document.querySelector('script[src*="autogram-sdk"]')
      if (existingScript) {
        existingScript.addEventListener("load", () => resolve(window.AutogramSDK))
        existingScript.addEventListener("error", () => reject(new Error(`Autogram SDK sa nepodarilo načítať z ${this.sdkPathValue}.`)))
        return
      }

      const script = document.createElement("script")
      script.src = this.sdkPathValue
      script.async = true
      script.addEventListener("load", () => resolve(window.AutogramSDK))
      script.addEventListener("error", () => reject(new Error(`Autogram SDK sa nepodarilo načítať z ${this.sdkPathValue}.`)))
      document.head.appendChild(script)
    })
  }

  buildDesktopClient(sdk) {
    if (typeof sdk?.DesktopClient !== "function") {
      throw new Error("Autogram SDK sa nepodarilo načítať")
    }

    return new sdk.DesktopClient()
  }

  handleDesktopState(state) {
    if (state.type === "checkingApp") {
      this.setStatusStage("checking")
      this.showNormalState(i18n.t("bundles.autogram_batch.waiting_for_app"))
      return
    }

    if (state.type === "launchingApp") {
      this.setStatusStage("starting")
      this.showNormalState(i18n.t("bundles.autogram_batch.waiting_for_app"))
      return
    }

    if (state.type === "waitingForSignature") {
      this.setStatusStage("sending")
      this.showNormalState(i18n.t("bundles.autogram_batch.awaiting_batch_confirmation"))
      return
    }

    if (state.type === "appNotInstalled") {
      this.showAppNotRunningState()
      return
    }

    if (state.type === "signingCancelled") {
      this.showCancelledState()
      return
    }

    if (state.type === "error") {
      this.showErrorState(state.message || i18n.t("bundles.autogram_batch.error_message"))
    }
  }

  isAppNotInstalledError(sdk, error) {
    if (!error) {
      return false
    }

    if (typeof sdk?.AutogramAppNotInstalledException === "function" && error instanceof sdk.AutogramAppNotInstalledException) {
      return true
    }

    return error.name === "AutogramAppNotInstalledException"
  }

  isUserCancelledError(sdk, error) {
    if (!error) {
      return false
    }

    if (typeof sdk?.UserCancelledSigningException === "function" && error instanceof sdk.UserCancelledSigningException) {
      return true
    }

    return error.name === "UserCancelledSigningException"
  }

  isAbortError(error) {
    return this.abortController?.signal.aborted || error?.name === "AbortError" || error?.message === "Aborted"
  }

  async loadAutogramParameters(path) {
    const response = await fetch(path, {
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').getAttribute("content")
      }
    })

    if (!response.ok) {
      throw new Error(i18n.t("errors.contract_load_failed"))
    }

    return await response.json()
  }

  async prepareSigningRequestBody(autogramParameters) {
    const documents = await Promise.all(autogramParameters.documents.map(async (document) => {
      return {
        ...document,
        content: await this.loadDocumentContent(document),
        payloadMimeType: document.content_type.includes("base64") ? document.content_type : `${document.content_type};base64`
      }
    }))

    const document = documents[0]

    return {
      document: {
        filename: document.filename,
        content: document.content
      },
      parameters: await this.signatureParameters(autogramParameters.signature_parameters, document.xdc_parameters),
      payloadMimeType: document.payloadMimeType
    }
  }

  async loadDocumentContent(document) {
    if (document.content) {
      return document.content
    }

    if (!document.download_url) {
      throw new Error(i18n.t("errors.contract_load_failed"))
    }

    const response = await fetch(document.download_url)
    if (!response.ok) {
      throw new Error(i18n.t("errors.file_read_failed"))
    }

    return await this.blobToBase64(await response.blob())
  }

  async signatureParameters(signatureParameters, xdcParameters) {
    const result = {
      level: `${signatureParameters.format}_${signatureParameters.level}`,
      container: signatureParameters.container
    }

    if (!xdcParameters) {
      result.autoLoadEform = true
      return result
    }

    result.autoLoadEform = xdcParameters.auto_load_eform
    result.containerXmlns = xdcParameters.container_xmlns
    result.embedUsedSchemas = xdcParameters.embed_used_schemas
    result.identifier = xdcParameters.identifier
    result.fsFormId = xdcParameters.fs_form_identifier
    result.schemaIdentifier = xdcParameters.schema_identifier
    result.transformationIdentifier = xdcParameters.transformation_identifier

    if (xdcParameters.schema != null) {
      if (xdcParameters.schema_mime_type?.includes("base64")) {
        result.schema = xdcParameters.schema
        result.transformation = xdcParameters.transformation
      } else {
        result.schema = await this.stringToBase64(xdcParameters.schema)
        result.schemaMimeType = `${xdcParameters.schema_mime_type};base64`
        result.transformation = await this.stringToBase64(xdcParameters.transformation)
        result.transformationMimeType = `${xdcParameters.transformation_mime_type};base64`
      }
    }

    return result
  }

  async uploadSignedDocument(path, content) {
    const formData = new FormData()
    formData.append("signed_document", content)

    const response = await fetch(path, {
      method: "POST",
      body: formData,
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').getAttribute("content"),
        Accept: "application/json"
      }
    })

    if (!response.ok) {
      let errorMessage = i18n.t("errors.signing_failed")

      try {
        const errorPayload = await response.json()
        errorMessage = errorPayload.error || errorMessage
      } catch {
      }

      throw new Error(errorMessage)
    }
  }

  updateProgress(completedCount, total, contractName = null) {
    const safeTotal = total || 1
    const percent = Math.round((completedCount / safeTotal) * 100)
    this.progressBarTarget.style.width = `${percent}%`
    this.progressPercentTarget.textContent = `${percent}%`
    this.progressTextTarget.textContent = i18n.t("bundles.autogram_batch.progress_step", {
      current: completedCount,
      total: total
    })

    if (contractName) {
      this.currentDocumentNameTarget.textContent = i18n.t("bundles.autogram_batch.current_document", {
        name: contractName
      })
    } else {
      this.currentDocumentNameTarget.textContent = ""
    }
  }

  setDocumentItemStates(activeIndex) {
    this.documentItemTargets.forEach((element, itemIndex) => {
      element.classList.remove("border-blue-300", "bg-blue-50", "border-green-300", "bg-green-50")

      if (itemIndex < activeIndex) {
        element.classList.add("border-green-300", "bg-green-50")
      } else if (itemIndex === activeIndex) {
        element.classList.add("border-blue-300", "bg-blue-50")
      }
    })
  }

  handleSuccess() {
    this.progressBarTarget.style.width = "100%"
    this.progressPercentTarget.textContent = "100%"
    this.setStatusStage("signed")
    this.documentItemTargets.forEach((element) => {
      element.classList.remove("border-blue-300", "bg-blue-50")
      element.classList.add("border-green-300", "bg-green-50")
    })

    if (this.iframeValue) {
      this.showSuccessState()
      window.parent.postMessage({
        type: "agp-custom-event",
        status: "document-signed",
        bundle_id: this.bundleIdValue,
        total_contracts_count: this.totalContractsCountValue,
        remaining_contracts_count: 0,
        bundle_completed: true,
        close_iframe: true
      }, "*")
      return
    }

    window.location.href = this.returnPathValue
  }

  showNormalState(message = null) {
    this.stateNormalTarget.classList.remove("hidden")
    this.stateAppNotRunningTarget.classList.add("hidden")
    this.stateSuccessTarget.classList.add("hidden")
    this.stateCancelledTarget.classList.add("hidden")
    this.stateErrorTarget.classList.add("hidden")

    if (message) {
      this.progressTextTarget.textContent = message
    }
  }

  showAppNotRunningState() {
    this.markStageFailed("starting")
    this.stateNormalTarget.classList.add("hidden")
    this.stateSuccessTarget.classList.add("hidden")
    this.stateCancelledTarget.classList.add("hidden")
    this.stateErrorTarget.classList.add("hidden")
    this.stateAppNotRunningTarget.classList.remove("hidden")
  }

  showSuccessState() {
    this.stateNormalTarget.classList.add("hidden")
    this.stateAppNotRunningTarget.classList.add("hidden")
    this.stateCancelledTarget.classList.add("hidden")
    this.stateErrorTarget.classList.add("hidden")
    this.stateSuccessTarget.classList.remove("hidden")
  }

  showCancelledState() {
    this.markStageFailed()
    this.stateNormalTarget.classList.add("hidden")
    this.stateAppNotRunningTarget.classList.add("hidden")
    this.stateSuccessTarget.classList.add("hidden")
    this.stateErrorTarget.classList.add("hidden")
    this.stateCancelledTarget.classList.remove("hidden")
  }

  showErrorState(message) {
    this.markStageFailed()
    this.stateNormalTarget.classList.add("hidden")
    this.stateAppNotRunningTarget.classList.add("hidden")
    this.stateSuccessTarget.classList.add("hidden")
    this.stateCancelledTarget.classList.add("hidden")
    this.stateErrorTarget.classList.remove("hidden")
    this.errorMessageTarget.textContent = message
  }

  hasStatusTimelineTargets() {
    return this.hasStatusCheckingTarget &&
      this.hasStatusStartingTarget &&
      this.hasStatusSendingTarget &&
      this.hasStatusWaitingTarget &&
      this.hasStatusSignedTarget
  }

  orderedStatusStages() {
    return [
      ["checking", this.statusCheckingTarget],
      ["starting", this.statusStartingTarget],
      ["sending", this.statusSendingTarget],
      ["waiting", this.statusWaitingTarget],
      ["signed", this.statusSignedTarget]
    ]
  }

  setStatusStage(stage) {
    if (!this.hasStatusTimelineTargets()) {
      return
    }

    this.currentStatusStage = stage
    const stages = this.orderedStatusStages()
    const activeIndex = stages.findIndex(([name]) => name === stage)

    stages.forEach(([_, element], index) => {
      if (stage === "signed" || index < activeIndex) {
        this.markCompleted(element)
      } else if (index === activeIndex) {
        this.markActive(element)
      } else {
        this.resetStatus(element)
      }
    })
  }

  markStageFailed(stage = this.currentStatusStage) {
    if (!this.hasStatusTimelineTargets()) {
      return
    }

    const stages = this.orderedStatusStages()
    const failedIndex = stages.findIndex(([name]) => name === stage)

    if (failedIndex === -1) {
      return
    }

    stages.forEach(([_, element], index) => {
      if (index < failedIndex) {
        this.markCompleted(element)
      } else if (index === failedIndex) {
        this.markFailed(element)
      } else {
        this.resetStatus(element)
      }
    })
  }

  resetStatus(element) {
    element.classList.remove("bg-green-50", "border-green-200")
    element.classList.remove("bg-white", "border-blue-200")
    element.classList.remove("bg-red-50", "border-red-200")
    element.classList.add("bg-gray-100", "border-gray-200", "opacity-50")

    const icon = element.querySelector(".flex-shrink-0")
    if (icon) {
      icon.innerHTML = '<div style="width: 24px; height: 24px;" class="bg-gray-400 rounded-full"></div>'
    }
  }

  markCompleted(element) {
    element.classList.remove("bg-gray-100", "border-gray-200", "opacity-50")
    element.classList.remove("bg-white", "border-blue-200")
    element.classList.remove("bg-red-50", "border-red-200")
    element.classList.add("bg-green-50", "border-green-200")

    const icon = element.querySelector(".flex-shrink-0")
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
    element.classList.remove("bg-gray-100", "border-gray-200", "opacity-50")
    element.classList.remove("bg-green-50", "border-green-200")
    element.classList.remove("bg-red-50", "border-red-200")
    element.classList.add("bg-white", "border-blue-200")

    const icon = element.querySelector(".flex-shrink-0")
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
    element.classList.remove("bg-gray-100", "border-gray-200", "opacity-50")
    element.classList.remove("bg-green-50", "border-green-200")
    element.classList.remove("bg-white", "border-blue-200")
    element.classList.add("bg-red-50", "border-red-200")

    const icon = element.querySelector(".flex-shrink-0")
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

  async stringToBase64(content) {
    return await this.blobToBase64(new File([content], "file"))
  }

  blobToBase64(blob) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader()
      reader.onloadend = () => {
        try {
          resolve(reader.result.split("base64,")[1])
        } catch (error) {
          reject(error)
        }
      }
      reader.onerror = () => reject(new Error(i18n.t("errors.file_read_failed")))
      reader.readAsDataURL(blob)
    })
  }
}