// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import Alpine from "alpinejs"
import i18n from "i18n"

// Make i18n available globally
window.i18n = i18n

// Start Alpine.js
window.Alpine = Alpine
Alpine.start()
