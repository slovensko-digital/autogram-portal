import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropzone", "fileInput", "documentsContainer", "submitButton", "fileName", "fileSize"]
  static classes = ["dragging", "uploading"]
  static values = { 
    mode: String,  // 'single' for documents, 'contract' for contracts with hidden inputs
    inputName: String  // for contract mode: base name like 'contract[documents_attributes]'
  }

  connect() {
    this.dragging = false
    this.uploading = false
    this.selectedFile = null
    this.updateUI()
  }

  click() {
    if (this.uploading) return
    this.fileInputTarget.click()
  }

  keydown(event) {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault()
      this.click()
    }
  }

  change(event) {
    if (this.uploading) return
    const file = event.target.files[0]
    if (file) {
      this.setFile(file)
    }
    if (this.modeValue === 'contract') {
      event.target.value = null
    }
  }

  dragover(event) {
    if (this.uploading) return
    event.preventDefault()
    this.setDragging(true)
  }

  dragleave(event) {
    if (this.uploading) return
    event.preventDefault()
    this.setDragging(false)
  }

  drop(event) {
    if (this.uploading) return
    event.preventDefault()
    this.setDragging(false)
    
    const files = event.dataTransfer.files
    if (files.length > 0) {
      const file = files[0]
      this.setFile(file)
    }
  }

  setFile(file) {
    if (this.isValidFileType(file)) {
      // Clear any existing file first
      this.clearFile()
      
      this.selectedFile = file
      this.updateFileInfo(file)
      
      if (this.modeValue === 'contract') {
        this.createHiddenInput(file)
      } else {
        this.updateFileInput(file)
      }
      
      this.updateUI()
      this.updateSubmitButton()
    } else {
      alert(`Súbor "${file.name}" nie je podporovaný. Povolené sú len PDF, XML a iné súbory.`)
    }
  }

  clearFile() {
    this.selectedFile = null
    
    if (this.modeValue === 'contract' && this.hasDocumentsContainerTarget) {
      this.documentsContainerTarget.innerHTML = ''
    } else {
      this.fileInputTarget.value = ''
    }
  }

  updateFileInfo(file) {
    if (this.hasFileNameTarget) {
      this.fileNameTarget.textContent = file.name
    }
    if (this.hasFileSizeTarget) {
      this.fileSizeTarget.textContent = this.formatFileSize(file.size)
    }
  }

  updateFileInput(file) {
    const dt = new DataTransfer()
    dt.items.add(file)
    this.fileInputTarget.files = dt.files
  }

  createHiddenInput(file) {
    if (!this.hasDocumentsContainerTarget) return
    
    const input = document.createElement('input')
    input.type = 'file'
    input.name = `${this.inputNameValue}[0][blob]`
    input.style.display = 'none'
    
    const dt = new DataTransfer()
    dt.items.add(file)
    input.files = dt.files
    
    this.documentsContainerTarget.appendChild(input)
  }

  isValidFileType(file) {
    const allowedTypes = [
      'application/pdf',
      'application/xml', 
      'text/xml',
      'application/vnd.gov.sk.xmldatacontainer+xml',
      'application/vnd.etsi.asic-e+zip',
      'text/plain',
      'image/png',
      'image/jpg',
      'image/jpeg'
    ]
    const allowedExtensions = ['.pdf', '.xml', '.xdcf', '.asice', '.txt', '.png', '.jpg', '.jpeg']
    
    return allowedTypes.includes(file.type) || 
           allowedExtensions.some(ext => file.name.toLowerCase().endsWith(ext))
  }

  removeFile(event) {
    event.stopPropagation()
    this.clearFile()
    this.updateUI()
    this.updateSubmitButton()
  }

  formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes'
    const k = 1024
    const sizes = ['Bytes', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i]
  }

  updateSubmitButton() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = !this.selectedFile
      if (!this.selectedFile) {
        this.submitButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
        this.submitButtonTarget.classList.remove('hover:bg-indigo-700')
      } else {
        this.submitButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
        this.submitButtonTarget.classList.add('hover:bg-indigo-700')
      }
    }
  }

  setDragging(value) {
    this.dragging = value
    this.updateUI()
  }

  setUploading(value) {
    this.uploading = value
    this.updateUI()
  }

  updateUI() {
    if (this.dragging && !this.selectedFile) {
      this.dropzoneTarget.classList.add(...this.draggingClasses)
      this.dropzoneTarget.classList.remove("border-dashed")
    } else if (this.uploading) {
      this.dropzoneTarget.classList.add(...this.uploadingClasses)
      this.dropzoneTarget.classList.remove("border-dashed", "cursor-pointer")
    } else if (this.selectedFile) {
      this.dropzoneTarget.classList.remove(...this.draggingClasses, ...this.uploadingClasses, "border-dashed")
      this.dropzoneTarget.classList.add("border-solid", "border-gray-300", "bg-gray-50")
    } else {
      this.dropzoneTarget.classList.remove(...this.draggingClasses, ...this.uploadingClasses, "border-solid", "border-gray-300", "bg-gray-50")
      this.dropzoneTarget.classList.add("border-dashed", "cursor-pointer")
    }

    const defaultState = this.dropzoneTarget.querySelector('.default-state')
    const draggingState = this.dropzoneTarget.querySelector('.dragging-state')
    const uploadingState = this.dropzoneTarget.querySelector('.uploading-state')
    const fileSelectedState = this.dropzoneTarget.querySelector('.file-selected-state')

    defaultState.classList.add('hidden')
    draggingState.classList.add('hidden')
    uploadingState.classList.add('hidden')
    fileSelectedState.classList.add('hidden')

    defaultState.classList.remove('flex')
    draggingState.classList.remove('flex')
    uploadingState.classList.remove('flex')
    fileSelectedState.classList.remove('flex')

    if (this.uploading) {
      uploadingState.classList.remove('hidden')
      uploadingState.classList.add('flex')
    } else if (this.selectedFile) {
      fileSelectedState.classList.remove('hidden')
      fileSelectedState.classList.add('flex')
    } else if (this.dragging) {
      draggingState.classList.remove('hidden')
      draggingState.classList.add('flex')
    } else {
      defaultState.classList.remove('hidden')
      defaultState.classList.add('flex')
    }
  }
}