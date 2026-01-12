// Simple i18n solution for JavaScript
// Translations are injected from Rails via a meta tag

class I18n {
  constructor() {
    this.translations = {}
    this.locale = 'en'
    
    // Load translations when DOM is ready
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', () => this.loadTranslations())
    } else {
      this.loadTranslations()
    }
  }

  loadTranslations() {
    const metaTag = document.querySelector('meta[name="i18n-translations"]')
    if (metaTag) {
      try {
        this.translations = JSON.parse(metaTag.content)
        console.log('i18n translations loaded:', this.translations)
      } catch (e) {
        console.error('Failed to parse i18n translations:', e)
      }
    } else {
      console.warn('i18n-translations meta tag not found')
    }

    const localeMeta = document.querySelector('meta[name="i18n-locale"]')
    if (localeMeta) {
      this.locale = localeMeta.content
    }
  }

  t(key, options = {}) {
    const keys = key.split('.')
    let translation = this.translations[this.locale]

    for (const k of keys) {
      if (translation && typeof translation === 'object') {
        translation = translation[k]
      } else {
        console.warn(`Translation missing: ${key}`)
        return key
      }
    }

    if (typeof translation !== 'string') {
      console.warn(`Translation is not a string: ${key}`)
      return key
    }

    // Handle interpolation
    return translation.replace(/%\{(\w+)\}/g, (match, variable) => {
      return options[variable] !== undefined ? options[variable] : match
    })
  }
}

// Create global instance
const i18n = new I18n()

// Reload translations on Turbo navigation
document.addEventListener('turbo:load', () => {
  i18n.loadTranslations()
})

export default i18n
