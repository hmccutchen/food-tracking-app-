// How the tag inputs (controllers/tags_controller.js) cut text into items:
// on commas, semicolons and new lines, but never inside brackets, so a food
// label's "wheat flour (enriched, niacin)" stays one item.

// "a, b (c, d); e\nf" -> ["a", "b (c, d)", "e", "f"]
export function split(text) {
  return splitKeepingLast(text).map((part) => part.trim()).filter((part) => part !== "")
}

// Like split, but the last piece is returned untrimmed and even when blank.
export function splitKeepingLast(text) {
  const parts = []
  let depth = 0
  let current = ""
  for (const char of String(text || "")) {
    if (char === "(" || char === "[") depth++
    if ((char === ")" || char === "]") && depth > 0) depth--
    if (depth === 0 && (char === "," || char === ";" || char === "\n")) {
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
