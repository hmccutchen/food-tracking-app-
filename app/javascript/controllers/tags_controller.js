import { Controller } from "@hotwired/stimulus"
import { insideBrackets, split, splitKeepingLast } from "lib/tag_split"

// Turns a comma-separated text field into tags: type an item, then a comma
// or Enter, and it becomes a chip with a remove button. Pasted lists (one per
// line or comma-separated) split the same way, using the field's own server
// separators (lib/tag_split.js). With data-tags-brackets-value="true" (a food
// label's ingredients), commas inside brackets stay with their item.
//
// The original field stays in the form (hidden) and always holds the tags
// joined with `joiner`, so the server sees exactly what it did before.
// Without JavaScript the plain field is left as it is.
export default class extends Controller {
  static values = { joiner: { type: String, default: ", " }, brackets: { type: Boolean, default: false } }

  connect() {
    this.field = this.element.querySelector("input[type='text'], textarea")
    if (!this.field) return

    this.splitOptions = { brackets: this.bracketsValue }
    this.tags = split(this.field.value, this.splitOptions)
    this.box = document.createElement("div")
    this.box.className = "tags"
    this.list = document.createElement("ul")
    this.list.className = "tag-list"
    this.input = document.createElement("input")
    this.input.type = "text"
    this.input.className = "tag-input"
    this.input.autocomplete = "off"
    this.input.id = `${this.field.id}_entry`
    this.input.placeholder = this.field.placeholder || "Type, then press comma or Enter"
    for (const name of [ "aria-describedby" ]) {
      if (this.field.hasAttribute(name)) this.input.setAttribute(name, this.field.getAttribute(name))
    }

    // The visible label now names the entry box; the hidden field keeps the value.
    this.label = this.element.querySelector(`label[for='${this.field.id}']`)
    if (this.label) this.label.htmlFor = this.input.id
    this.required = this.field.hasAttribute("required")
    this.field.hidden = true
    this.field.removeAttribute("required")

    this.box.append(this.list, this.input)
    this.field.after(this.box)

    this.onKeydown = this.keydown.bind(this)
    this.onInput = this.typed.bind(this)
    this.onPaste = this.pasted.bind(this)
    this.onBlur = () => this.commit(this.input.value)
    this.onBoxClick = (event) => { if (event.target === this.box || event.target === this.list) this.input.focus() }
    this.onSubmit = () => this.commit(this.input.value)
    this.input.addEventListener("keydown", this.onKeydown)
    this.input.addEventListener("input", this.onInput)
    this.input.addEventListener("paste", this.onPaste)
    this.input.addEventListener("blur", this.onBlur)
    this.box.addEventListener("click", this.onBoxClick)
    this.field.form?.addEventListener("submit", this.onSubmit, true)

    this.render()
  }

  // Undo everything, so a page restored from Turbo's cache starts clean.
  disconnect() {
    if (!this.box) return
    this.commit(this.input.value)
    this.field.form?.removeEventListener("submit", this.onSubmit, true)
    if (this.label) this.label.htmlFor = this.field.id
    if (this.required) this.field.setAttribute("required", "")
    this.field.hidden = false
    this.box.remove()
    this.box = null
  }

  keydown(event) {
    const separator = event.key === "," || event.key === ";"
    const beforeCaret = this.input.value.slice(0, this.input.selectionStart ?? this.input.value.length)
    if (event.key === "Enter" || (separator && !(this.bracketsValue && insideBrackets(beforeCaret)))) {
      event.preventDefault()
      this.commit(this.input.value)
    } else if (event.key === "Backspace" && this.input.value === "" && this.tags.length > 0) {
      this.remove(this.tags.length - 1)
    }
  }

  // Pasted (or autocorrected) text with separators in it becomes tags,
  // except the last piece, which may still be being typed.
  typed() {
    const parts = splitKeepingLast(this.input.value, this.splitOptions)
    if (parts.length < 2) return

    this.input.value = parts.pop()
    this.add(parts)
  }

  // A one-line box drops pasted line breaks, so a pasted list is split here,
  // from the clipboard text, before the box sees it. A pasted list is taken
  // as complete: every item, the last one too, becomes a tag.
  pasted(event) {
    const text = event.clipboardData?.getData("text") || ""
    if (!/[,;\n\r]/.test(text)) return

    event.preventDefault()
    const { value, selectionStart, selectionEnd } = this.input
    const start = selectionStart ?? value.length
    const end = selectionEnd ?? value.length
    this.commit(value.slice(0, start) + text + value.slice(end))
  }

  commit(text) {
    if (!this.box) return
    this.input.value = ""
    this.add(split(text, this.splitOptions))
  }

  add(items) {
    const known = new Set(this.tags.map((tag) => tag.toLowerCase()))
    let changed = false
    for (const item of items) {
      if (known.has(item.toLowerCase())) continue
      known.add(item.toLowerCase())
      this.tags.push(item)
      changed = true
    }
    if (changed) this.render()
  }

  remove(index) {
    this.tags.splice(index, 1)
    this.render()
    this.input.focus()
  }

  render() {
    this.list.replaceChildren(...this.tags.map((tag, index) => {
      const item = document.createElement("li")
      item.className = "tag"
      const text = document.createElement("span")
      text.textContent = tag
      const button = document.createElement("button")
      button.type = "button"
      button.className = "tag-remove"
      button.textContent = "×"
      button.setAttribute("aria-label", `Remove ${tag}`)
      // Keep focus in the entry box: a blur would commit a half-typed item and
      // redraw the chips before this click lands, so it would miss.
      button.addEventListener("mousedown", (event) => event.preventDefault())
      button.addEventListener("click", () => this.remove(index))
      item.append(text, button)
      return item
    }))
    this.input.required = this.required && this.tags.length === 0
    this.field.value = this.tags.join(this.joinerValue)
    this.field.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
