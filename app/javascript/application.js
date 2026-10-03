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

// Keep keyboard and screen reader users oriented when a user action swaps a Turbo Frame:
// move focus to the new step heading (instead of losing it to <body>) and update the page title.
let focusNextFrameLoad = false
document.addEventListener("turbo:click", () => { focusNextFrameLoad = true })
document.addEventListener("turbo:submit-start", () => { focusNextFrameLoad = true })
document.addEventListener("turbo:load", () => { focusNextFrameLoad = false })
document.addEventListener("turbo:frame-load", (event) => {
  if (!focusNextFrameLoad) return
  focusNextFrameLoad = false

  const active = document.activeElement
  if (active && active !== document.body && active.isConnected) return

  const heading = event.target.querySelector("h1, h2, h3")
  if (!heading) return

  heading.setAttribute("tabindex", "-1")
  heading.classList.add("focus:outline-none")
  heading.focus()
  document.title = `${heading.textContent.trim()} – Autogram Portal`
})

// When embedded via the SDK popup, let Escape inside the portal close the integrator's popup.
if (window.self !== window.top) {
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !event.defaultPrevented) {
      window.parent.postMessage({ type: "agp-escape" }, "*")
    }
  })
}
