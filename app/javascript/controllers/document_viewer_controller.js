import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["documentItem", "documentContent"]

  connect() {
    this.showDocument(0) // Show first document by default
  }

  selectDocument(event) {
    const clickedItem = event.currentTarget
    const documentId = clickedItem.dataset.documentId
    const documentIndex = parseInt(clickedItem.dataset.documentIndex)

    this.updateActiveStates(clickedItem, documentId)
    this.showDocument(documentIndex)
  }

  updateActiveStates(activeItem, documentId) {
    this.documentItemTargets.forEach(item => {
      item.classList.remove('ring-2', 'ring-blue-500', 'bg-blue-50', 'border-blue-300')
      item.classList.add('border-gray-200', 'bg-white')
    })

    activeItem.classList.add('ring-2', 'ring-blue-500', 'bg-blue-50', 'border-blue-300')
    activeItem.classList.remove('border-gray-200', 'bg-white')
  }

  showDocument(index) {
    this.documentContentTargets.forEach(content => {
      content.classList.add('hidden')
    })

    if (this.documentContentTargets[index]) {
      this.documentContentTargets[index].classList.remove('hidden')
    }
  }
}