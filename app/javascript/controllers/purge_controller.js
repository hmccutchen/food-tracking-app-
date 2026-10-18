import { Controller } from "@hotwired/stimulus"
import { purgeEverywhere } from "pwa/client"

// On the sign-in page: a backstop that deletes any saved avoid lists left
// behind, e.g. when the session expired without a sign-out.
export default class extends Controller {
  async connect() {
    await purgeEverywhere(1500)
    this.element.dataset.purged = "true"
  }
}
