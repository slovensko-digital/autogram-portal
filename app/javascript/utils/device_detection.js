// Phones and tablets, which cannot run desktop apps such as Autogram.
export function isMobileDevice() {
  const userAgent = navigator.userAgent || navigator.vendor || window.opera
  const mobileRegex = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i
  const isMobileUA = mobileRegex.test(userAgent)
  const isTouchDevice = 'ontouchstart' in window || navigator.maxTouchPoints > 0
  const isSmallScreen = window.innerWidth <= 768
  const hasMobileFeatures = 'orientation' in window || 'DeviceMotionEvent' in window

  return isMobileUA || isTabletDevice() || (isTouchDevice && isSmallScreen && hasMobileFeatures)
}

export function isTabletDevice() {
  const userAgent = navigator.userAgent || navigator.vendor || window.opera
  if (/iPad|Tablet|PlayBook|Silk|Kindle/i.test(userAgent)) return true
  // Android phones put "Mobile" in the user agent, Android tablets do not.
  if (/Android/i.test(userAgent) && !/Mobile/i.test(userAgent)) return true
  // iPadOS Safari identifies itself as desktop Safari on a Mac, which has no touch screen.
  return /Macintosh/i.test(userAgent) && navigator.maxTouchPoints > 1
}

// Phones can sign in a mobile app themselves; tablets usually have no NFC to read the ID card, so they show a QR code for a phone instead.
export function isPhoneDevice() {
  return isMobileDevice() && !isTabletDevice()
}
