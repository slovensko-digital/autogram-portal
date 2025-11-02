export function isMobileDevice() {
  const userAgent = navigator.userAgent || navigator.vendor || window.opera
  const mobileRegex = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
  const isMobileUA = mobileRegex.test(userAgent)
  const isTouchDevice = 'ontouchstart' in window || navigator.maxTouchPoints > 0
  const isSmallScreen = window.innerWidth <= 768
  const hasMobileFeatures = 'orientation' in window || 'DeviceMotionEvent' in window

  return isMobileUA || (isTouchDevice && isSmallScreen && hasMobileFeatures)
}
