export function isMobileDevice() {
  const userAgent = navigator.userAgent || navigator.vendor || window.opera
  const mobileRegex = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
  const isMobileUA = mobileRegex.test(userAgent)
  const isTouchDevice = 'ontouchstart' in window || navigator.maxTouchPoints > 0
  const isSmallScreen = window.innerWidth <= 768
  const hasMobileFeatures = 'orientation' in window || 'DeviceMotionEvent' in window

  return isMobileUA || (isTouchDevice && isSmallScreen && hasMobileFeatures)
}

export function isActualMobileDevice() {
  // Check only user agent to determine if it's truly a mobile device
  // This is useful for features that should behave differently on desktop vs mobile
  // regardless of screen size (e.g., in narrow iframes)
  const userAgent = navigator.userAgent || navigator.vendor || window.opera
  const mobileRegex = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
  return mobileRegex.test(userAgent)
}
