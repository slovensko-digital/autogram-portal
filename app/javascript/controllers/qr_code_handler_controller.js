import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  handleClick(event) {
    const avmUrl = this.data.get("avm-url")
    
    if (this.isMobileDevice() && avmUrl) {
      // On mobile devices, we can enhance the experience
      console.log("QR code clicked on mobile device, opening AVM URL:", avmUrl)
      
      // Optional: Add some visual feedback
      this.element.style.transform = "scale(0.95)"
      setTimeout(() => {
        this.element.style.transform = "scale(1)"
      }, 150)
      
      // The default link behavior will handle opening the URL
      // but we could add additional mobile-specific logic here if needed
    }
  }

  isMobileDevice() {
    // Same mobile detection logic as in avm_signer_controller
    const userAgent = navigator.userAgent || navigator.vendor || window.opera
    const mobileRegex = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
    const isMobileUA = mobileRegex.test(userAgent)
    const isTouchDevice = 'ontouchstart' in window || navigator.maxTouchPoints > 0
    const isSmallScreen = window.innerWidth <= 768
    const hasMobileFeatures = 'orientation' in window || 'DeviceMotionEvent' in window
    
    return isMobileUA || (isTouchDevice && isSmallScreen && hasMobileFeatures)
  }
}