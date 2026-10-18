import { Controller } from "@hotwired/stimulus"
import { purgeEverywhere } from "pwa/client"

// Holds the sign-out form until saved avoid lists are deleted (or a short
// timeout passes), then submits it for real.
export default class extends Controller {
  async submit(event) {
    if (this.purged) return
    event.preventDefault()
    event.stopImmediatePropagation()
    try {
      await purgeEverywhere(1500)
    } finally {
      // Sign out whatever happened to the cache clean-up.
      this.purged = true
      this.element.requestSubmit()
    }
  }
}
