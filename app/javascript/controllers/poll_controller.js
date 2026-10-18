import { Controller } from "@hotwired/stimulus"

// No-websocket fallback for "Finding meals…": reloads the enclosing
// turbo-frame from urlValue every intervalValue ms. The reloaded frame only
// carries this controller again while the request is still queued/running,
// so polling stops by itself once results are in (or a broadcast lands).
export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 3000 } }

  connect() {
    this.timer = setTimeout(() => this.reload(), this.intervalValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  reload() {
    const frame = this.element.closest("turbo-frame")
    if (!frame || !this.element.isConnected) return

    if (frame.getAttribute("src")) {
      frame.reload()
    } else {
      frame.src = this.urlValue
    }
  }
}
