import { Controller } from "@hotwired/stimulus"

// The "choose items" checklist: a search box that hides items with no word
// starting with what was typed ("almo" finds almond, not salmon) and sections
// left empty, and a live count of ticked items.
// Without JavaScript every item stays visible and the form works the same.
export default class extends Controller {
  static targets = ["filter", "item", "section", "count", "empty"]

  filter() {
    const query = this.filterTarget.value.trim().toLowerCase()
    let anyShown = false
    for (const section of this.sectionTargets) {
      let shown = 0
      for (const item of section.querySelectorAll("[data-picker-target~='item']")) {
        const match = query === "" || ` ${item.dataset.name.toLowerCase().replace(/[-/]/g, " ")}`.includes(` ${query}`)
        item.hidden = !match
        if (match) shown++
      }
      section.hidden = shown === 0
      anyShown ||= shown > 0
    }
    this.emptyTarget.hidden = anyShown
  }

  count() {
    const ticked = this.element.querySelectorAll("input[type='checkbox'][name='node_ids[]']:checked").length
    this.countTarget.textContent = `${ticked} ${ticked === 1 ? "item" : "items"} ticked`
  }
}
