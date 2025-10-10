import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  handleClick(event) {
    const avmUrl = this.data.get("avm-url")
    
    if (this.isMobileDevice() && avmUrl) {
      console.log("QR code clicked on mobile device, opening AVM URL:", avmUrl)
      
      this.element.style.transform = "scale(0.95)"
      setTimeout(() => {
        this.element.style.transform = "scale(1)"
      }, 150)
    }
  }

  isMobileDevice() {
    const userAgent = navigator.userAgent || navigator.vendor || window.opera
    const mobileRegex = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
    const isMobileUA = mobileRegex.test(userAgent)
    const isTouchDevice = 'ontouchstart' in window || navigator.maxTouchPoints > 0
    const isSmallScreen = window.innerWidth <= 768
    const hasMobileFeatures = 'orientation' in window || 'DeviceMotionEvent' in window
    
    return isMobileUA || (isTouchDevice && isSmallScreen && hasMobileFeatures)
  }
}