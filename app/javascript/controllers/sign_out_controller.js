import { Controller } from "@hotwired/stimulus"
import { purgeEverywhere } from "pwa/client"

// Holds the sign-out form until saved avoid lists are deleted (or a short
// timeout passes), then submits it for real.
export default class extends Controller {
  async submit(event) {
    if (this.purged) return
    event.preventDefault()
    event.stopImmediatePropagation()
    await purgeEverywhere(1500)
    this.purged = true
    this.element.requestSubmit()
  }
}
