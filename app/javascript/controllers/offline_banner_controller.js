import { Controller } from "@hotwired/stimulus"
import { savedAt } from "pwa/client"

// Shows "You're offline" while the browser reports no network. On the avoid
// list, it also says when the saved copy was made.
export default class extends Controller {
  connect() {
    this.update = this.update.bind(this)
    window.addEventListener("online", this.update)
    window.addEventListener("offline", this.update)
    this.update()
  }

  disconnect() {
    window.removeEventListener("online", this.update)
    window.removeEventListener("offline", this.update)
  }

  async update() {
    if (navigator.onLine) {
      this.element.hidden = true
      return
    }
    const builtAt = document.querySelector("#list_built_at time")
    let text = "You're offline."
    if (builtAt) {
      const when = (await savedAt(window.location.href)) || builtAt.dateTime
      text = `You're offline — showing the list saved at ${formatTime(when)}`
    }
    this.element.textContent = text
    this.element.hidden = false
  }
}

function formatTime(value) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return "an earlier time"
  return date.toLocaleString([], { dateStyle: "medium", timeStyle: "short" })
}
