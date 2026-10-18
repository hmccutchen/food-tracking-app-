import { Controller } from "@hotwired/stimulus"
import { SERVICE_WORKER_URL, postToWorker, purgeLocally, supported } from "pwa/client"

const SWEEP_EVERY_MS = 10 * 60 * 1000

// On every signed-in page: registers the service worker and tells it a
// session is active and whether offline caching is on. The worker caches
// nothing until it hears this. Also asks it to sweep expired lists now and
// every 10 minutes while the page is open.
export default class extends Controller {
  static values = { offlineCaching: Boolean }

  async connect() {
    if (!supported()) return
    this.element.dataset.pwaState = "registering"
    if (!this.offlineCachingValue) await purgeLocally()

    try {
      await navigator.serviceWorker.register(SERVICE_WORKER_URL, { type: "module", scope: "/" })
      const registration = await navigator.serviceWorker.ready
      const reply = await postToWorker(
        { type: "session", signedIn: true, offlineCaching: this.offlineCachingValue },
        { worker: registration.active }
      )
      this.element.dataset.pwaState = reply ? "ready" : "no-reply"
      await this.sweep()
    } catch (error) {
      this.element.dataset.pwaState = "failed"
      console.warn("Offline support is unavailable:", error)
      return
    }

    this.timer = setInterval(() => this.sweep(), SWEEP_EVERY_MS)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  async sweep() {
    return postToWorker({ type: "sweep" })
  }
}
