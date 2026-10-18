// How the tag inputs (controllers/tags_controller.js) cut text into items:
// on commas, semicolons and new lines, the same separators the server's
// parsers use, so each chip is exactly one saved or checked item.
//
// With { brackets: true } (only for a food label's ingredients, which the
// server splits on brackets as well), commas inside brackets don't split, so
// "wheat flour (enriched, niacin)" stays one line of the label.

const SEPARATORS = new Set([ ",", ";", "\n", "\r" ])

// "a, b; c\nd" -> ["a", "b", "c", "d"]
export function split(text, options = {}) {
  return splitKeepingLast(text, options).map((part) => part.trim()).filter((part) => part !== "")
}

// Like split, but the last piece is returned untrimmed and even when blank.
export function splitKeepingLast(text, { brackets = false } = {}) {
  const parts = []
  let depth = 0
  let current = ""
  for (const char of String(text || "")) {
    if (brackets && (char === "(" || char === "[")) depth++
    if (brackets && (char === ")" || char === "]") && depth > 0) depth--
    if (depth === 0 && SEPARATORS.has(char)) {
      parts.push(current.trim())
      current = ""
    } else {
      current += char
    }
  }
  return [ ...parts.filter((part) => part !== ""), current.trimStart() ]
}

// True while a "(" or "[" is still open, e.g. "wheat flour (enriched".
export function insideBrackets(text) {
  let depth = 0
  for (const char of String(text || "")) {
    if (char === "(" || char === "[") depth++
    if ((char === ")" || char === "]") && depth > 0) depth--
  }
  return depth > 0
}
