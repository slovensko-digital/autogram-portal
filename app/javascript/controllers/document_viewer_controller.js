import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="document-viewer"
export default class extends Controller {
  static targets = ["documentItem", "documentContent"]

  connect() {
    this.showDocument(0) // Show first document by default
  }

  selectDocument(event) {
    const clickedItem = event.currentTarget
    const documentId = clickedItem.dataset.documentId
    const documentIndex = parseInt(clickedItem.dataset.documentIndex)

    // Update active states
    this.updateActiveStates(clickedItem, documentId)
    
    // Show the selected document
    this.showDocument(documentIndex)
  }

  updateActiveStates(activeItem, documentId) {
    // Remove active state from all items
    this.documentItemTargets.forEach(item => {
      item.classList.remove('ring-2', 'ring-blue-500', 'bg-blue-50', 'border-blue-300')
      item.classList.add('border-gray-200', 'bg-white')
    })

    // Add active state to clicked item
    activeItem.classList.add('ring-2', 'ring-blue-500', 'bg-blue-50', 'border-blue-300')
    activeItem.classList.remove('border-gray-200', 'bg-white')
  }

  showDocument(index) {
    // Hide all document content
    this.documentContentTargets.forEach(content => {
      content.classList.add('hidden')
    })

    // Show the selected document content
    if (this.documentContentTargets[index]) {
      this.documentContentTargets[index].classList.remove('hidden')
    }
  }
}