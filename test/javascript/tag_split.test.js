// Run with: node --test test/javascript/
import { test } from "node:test"
import assert from "node:assert/strict"
import { insideBrackets, split, splitKeepingLast } from "../../app/javascript/lib/tag_split.js"

test("splits on commas, semicolons and new lines, trimming and dropping blanks", () => {
  assert.deepEqual(split(" almond flour, soy sauce;milk\n\n eggs ,"), [ "almond flour", "soy sauce", "milk", "eggs" ])
  assert.deepEqual(split(""), [])
  assert.deepEqual(split(null), [])
})

test("with brackets: true, keeps commas inside brackets, as on a food label", () => {
  const brackets = { brackets: true }
  assert.deepEqual(split("wheat flour (enriched, niacin), salt, spices [paprika, cumin]", brackets),
    [ "wheat flour (enriched, niacin)", "salt", "spices [paprika, cumin]" ])
  assert.deepEqual(split("oddly) closed, fine", brackets), [ "oddly) closed", "fine" ])
})

// Other names, check ingredients and keywords are split server-side on every
// separator, so their chips must be too: one chip, one saved item.
test("by default, splits on every separator like the server parsers do", () => {
  assert.deepEqual(split("soup (mild, spicy)"), [ "soup (mild", "spicy)" ])
  assert.deepEqual(split("milk\r\nsalt"), [ "milk", "salt" ])
})

test("leaves the piece still being typed for the entry box", () => {
  assert.deepEqual(splitKeepingLast("almond, soy sau"), [ "almond", "soy sau" ])
  assert.deepEqual(splitKeepingLast("almond,"), [ "almond", "" ])
  assert.deepEqual(splitKeepingLast("almond"), [ "almond" ])
  assert.deepEqual(splitKeepingLast("milk\nsalt\n"), [ "milk", "salt", "" ])
})

test("knows when a bracket is still open, so a typed comma stays in the item", () => {
  assert.equal(insideBrackets("wheat flour (enriched"), true)
  assert.equal(insideBrackets("wheat flour (enriched, niacin)"), false)
  assert.equal(insideBrackets("spices [paprika"), true)
  assert.equal(insideBrackets("almond"), false)
})
