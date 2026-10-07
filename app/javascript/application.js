// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "altcha"
import Alpine from "alpinejs"
import i18n from "i18n"

// Make i18n available globally
window.i18n = i18n

// Start Alpine.js
window.Alpine = Alpine
Alpine.start()

// Keep keyboard and screen reader users oriented when a user action swaps a Turbo Frame or Turbo Drive
// renders a new page: move focus to the new heading (instead of losing it to <body>).
function focusHeading(heading) {
  heading.setAttribute("tabindex", "-1")
  heading.classList.add("focus:outline-none")
  heading.focus({ preventScroll: true })
}

function focusLost() {
  const active = document.activeElement
  return !active || active === document.body || !active.isConnected
}

let focusNextFrameLoad = false
document.addEventListener("turbo:click", () => { focusNextFrameLoad = true })
document.addEventListener("turbo:submit-start", () => { focusNextFrameLoad = true })
document.addEventListener("turbo:frame-load", (event) => {
  if (!focusNextFrameLoad) return
  focusNextFrameLoad = false

  // A frame replaced by a user action starts like a new page (e.g. a signing app after "Pokračovať" at the bottom
  // of the list), so show its beginning. Only this document scrolls, not an integrator page embedding it.
  const frameTop = event.target.getBoundingClientRect().top
  if (frameTop < 0) window.scrollTo({ top: window.scrollY + frameTop })

  if (!focusLost()) return

  const heading = event.target.querySelector("h1, h2, h3")
  if (!heading) return

  focusHeading(heading)
  document.title = `${heading.textContent.trim()} – Autogram Portal`
})

// Turbo Drive visits (e.g. "Pokračovať na podpisovanie" → …/sign). The initial page load has no visit timing
// and is left to the browser; pages that focus something themselves (autofocus, an anchor) are left alone.
document.addEventListener("turbo:load", (event) => {
  focusNextFrameLoad = false
  if (!("visitStart" in (event.detail?.timing || {}))) return
  if (window.location.hash || !focusLost()) return

  const main = document.getElementById("main-content")
  if (!main) return

  const heading = main.querySelector("h1")
  if (heading) {
    focusHeading(heading)
  } else {
    main.focus({ preventScroll: true })
  }
})

// When embedded via the SDK popup, let Escape inside the portal close the integrator's popup.
if (window.self !== window.top) {
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !event.defaultPrevented) {
      window.parent.postMessage({ type: "agp-escape" }, "*")
    }
  })
}
