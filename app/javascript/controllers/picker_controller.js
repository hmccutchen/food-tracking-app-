import { Controller } from "@hotwired/stimulus"

// The "choose items" checklist: a search box that hides items with no word
// starting with what was typed ("almo" finds almond, not salmon) and sections
// left empty, and a live count of ticked items.
// Without JavaScript every item stays visible and the form works the same.
export default class extends Controller {
  static targets = ["filter", "item", "section", "count", "empty"]

  filter() {
    const query = this.filterTarget.value.trim().toLowerCase()
    // Items nest (a group holds what it covers). Children come after their
    // group in document order, so walking backwards decides every child
    // first; a group stays visible when it or anything inside it matches.
    for (const item of [ ...this.itemTargets ].reverse()) {
      const own = query === "" || ` ${item.dataset.name.toLowerCase().replace(/[-/]/g, " ")}`.includes(` ${query}`)
      const childShown = item.querySelector(":scope > ul > li:not([hidden])") !== null
      item.hidden = !(own || childShown)
    }
    let anyShown = false
    for (const section of this.sectionTargets) {
      section.hidden = section.querySelector(":scope > ul > li:not([hidden])") === null
      anyShown ||= !section.hidden
    }
    this.emptyTarget.hidden = anyShown
  }

  count() {
    const ticked = this.element.querySelectorAll("input[type='checkbox'][name='node_ids[]']:checked").length
    this.countTarget.textContent = `${ticked} ${ticked === 1 ? "item" : "items"} ticked`
  }
}
