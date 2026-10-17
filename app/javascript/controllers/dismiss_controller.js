import { Controller } from "@hotwired/stimulus"

// Hides an advisory note and remembers its key so it stays hidden next time.
// Storage can be unavailable (private mode, blocked); the note still hides.
const STORAGE_KEY = "dismissed-prep-notes"

function readDismissed() {
  try {
    const list = JSON.parse(window.localStorage.getItem(STORAGE_KEY) || "[]")
    return Array.isArray(list) ? list : []
  } catch (_error) {
    return []
  }
}

export default class extends Controller {
  static values = { key: String }

  connect() {
    if (this.keyValue && readDismissed().includes(this.keyValue)) this.element.hidden = true
  }

  dismiss() {
    this.element.hidden = true
    if (!this.keyValue) return

    try {
      const list = readDismissed().filter((key) => key !== this.keyValue)
      list.push(this.keyValue)
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(list.slice(-200)))
    } catch (_error) {
      // Not remembered; hidden for now only.
    }
  }
}
