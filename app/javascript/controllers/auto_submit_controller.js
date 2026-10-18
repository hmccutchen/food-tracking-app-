import { Controller } from "@hotwired/stimulus"

// Submits the form whenever an input changes. The "Update" button stays as the
// no-JavaScript fallback and is hidden once this controller runs.
export default class extends Controller {
  static targets = ["button"]

  connect() {
    if (this.hasButtonTarget) this.buttonTarget.hidden = true
  }

  submit() {
    this.element.requestSubmit()
  }
}
