// Run with: node --test test/javascript/
import { test } from "node:test"
import assert from "node:assert/strict"
import * as policy from "../../app/javascript/pwa/cache_policy.js"

const ORIGIN = "https://meals.example"
const HOUR = 60 * 60 * 1000
const now = Date.parse("2026-10-18T12:00:00Z")

function response({ status = 200, url = `${ORIGIN}/group?patient_ids[]=1`, redirected = false,
  type = "basic", contentType = "text/html; charset=utf-8" } = {}) {
  return { status, url, redirected, type, headers: new Map([ [ "content-type", contentType ] ]) }
}

test("only GET /group (with or without a selection) is cacheable", () => {
  assert.equal(policy.isCacheableRequest(`${ORIGIN}/group?patient_ids[]=1&patient_ids[]=2`, "GET", ORIGIN), true)
  assert.equal(policy.isCacheableRequest(`${ORIGIN}/group`, "get", ORIGIN), true)
  assert.equal(policy.isCacheableRequest(`${ORIGIN}/group/check`, "POST", ORIGIN), false)
  assert.equal(policy.isCacheableRequest(`${ORIGIN}/group?patient_ids[]=1`, "POST", ORIGIN), false)
  assert.equal(policy.isCacheableRequest(`${ORIGIN}/group/check`, "GET", ORIGIN), false)
  assert.equal(policy.isCacheableRequest("https://elsewhere.example/group", "GET", ORIGIN), false)
  assert.equal(policy.isCacheableRequest("not a url", "GET", ORIGIN), false)
})

test("settings, sign-in, patients, foods, custom items and meal requests are network-only", () => {
  for (const path of [ "/settings/ai", "/settings/offline", "/users/sign_in", "/users/sign_out", "/account/edit", "/patients", "/patients/1",
    "/foods?q=almond", "/custom-items", "/meal-requests/3", "/", "/passwords/new", "/groups" ]) {
    assert.equal(policy.isCacheableRequest(`${ORIGIN}${path}`, "GET", ORIGIN), false, path)
  }
})

test("only plain 200 HTML avoid-list responses are stored", () => {
  assert.equal(policy.isCacheableResponse(response()), true)
  assert.equal(policy.isCacheableResponse(response({ status: 401 })), false)
  assert.equal(policy.isCacheableResponse(response({ status: 403 })), false)
  assert.equal(policy.isCacheableResponse(response({ status: 500 })), false)
  assert.equal(policy.isCacheableResponse(response({ status: 0, type: "opaqueredirect" })), false)
  assert.equal(policy.isCacheableResponse(response({ redirected: true, url: `${ORIGIN}/users/sign_in` })), false)
  assert.equal(policy.isCacheableResponse(response({ redirected: true, url: `${ORIGIN}/patients` })), false)
  assert.equal(policy.isCacheableResponse(response({ contentType: "application/json" })), false)
  assert.equal(policy.isCacheableResponse(null), false)
})

test("a 401 or landing on sign-in purges; ordinary responses do not", () => {
  assert.equal(policy.shouldPurgeFor(response({ status: 401 }), `${ORIGIN}/group`), true)
  assert.equal(policy.shouldPurgeFor(response({ redirected: true, url: `${ORIGIN}/users/sign_in` }), `${ORIGIN}/group`), true)
  assert.equal(policy.shouldPurgeFor(response({ url: `${ORIGIN}/users/sign_in` }), `${ORIGIN}/users/sign_in`), true)
  assert.equal(policy.shouldPurgeFor(response(), `${ORIGIN}/group?patient_ids[]=1`), false)
  assert.equal(policy.shouldPurgeFor(response({ status: 403 }), `${ORIGIN}/patients/9`), false)
  assert.equal(policy.shouldPurgeFor(response({ redirected: true, url: `${ORIGIN}/group?patient_ids[]=1` }),
    `${ORIGIN}/group`), false)
  assert.equal(policy.shouldPurgeFor(null), false)
})

test("entries expire at 24 hours; missing or unreadable stamps count as expired", () => {
  assert.equal(policy.isExpired(new Date(now - 23 * HOUR).toISOString(), now), false)
  assert.equal(policy.isExpired(now - 24 * HOUR, now), true)
  assert.equal(policy.isExpired(new Date(now - 25 * HOUR).toISOString(), now), true)
  assert.equal(policy.isExpired(null, now), true)
  assert.equal(policy.isExpired(undefined, now), true)
  assert.equal(policy.isExpired("yesterday-ish", now), true)
  assert.equal(policy.isExpired(now + 2 * HOUR, now), true, "a stamp from the future is not trusted")
})

test("trimToNewest keeps the newest five, newest first", () => {
  const entries = Array.from({ length: 7 }, (_, i) => ({ url: `/group?i=${i}`, cachedAt: now - i * HOUR }))
  const kept = policy.trimToNewest([ ...entries ].reverse(), 5)
  assert.deepEqual(kept.map((entry) => entry.url), [ 0, 1, 2, 3, 4 ].map((i) => `/group?i=${i}`))
  assert.equal(policy.trimToNewest(entries, 0).length, 0)
})

test("a sweep deletes expired entries and anything beyond five", () => {
  const entries = [
    { url: "a", cachedAt: new Date(now - 25 * HOUR).toISOString() },
    { url: "b", cachedAt: now - 1 * HOUR },
    { url: "c", cachedAt: now - 2 * HOUR },
    { url: "d", cachedAt: now - 3 * HOUR },
    { url: "e", cachedAt: now - 4 * HOUR },
    { url: "f", cachedAt: now - 5 * HOUR },
    { url: "g", cachedAt: now - 6 * HOUR },
    { url: "h", cachedAt: null }
  ]
  assert.deepEqual(policy.entriesToDelete(entries, now).sort(), [ "a", "g", "h" ])
  assert.deepEqual(policy.entriesToDelete([ { url: "b", cachedAt: now } ], now), [])
})

test("the worker starts signed out and caches nothing until a session message", () => {
  const start = policy.initialState()
  assert.equal(policy.mayCache(start), false)

  const on = policy.applyMessage(start, { type: "session", signedIn: true, offlineCaching: true })
  assert.equal(policy.mayCache(on.state), true)
  assert.equal(on.purge, false)

  const off = policy.applyMessage(on.state, { type: "session", signedIn: true, offlineCaching: false })
  assert.equal(policy.mayCache(off.state), false)
  assert.equal(off.purge, true, "turning the setting off deletes avoid-lists")

  const purged = policy.applyMessage(on.state, { type: "purge" })
  assert.equal(policy.mayCache(purged.state), false)
  assert.equal(purged.purge, true)

  const signedOut = policy.applyMessage(on.state, { type: "session", signedIn: false, offlineCaching: true })
  assert.equal(policy.mayCache(signedOut.state), false)
  assert.equal(signedOut.purge, true)

  const unknown = policy.applyMessage(on.state, { type: "hello" })
  assert.deepEqual(unknown.state, on.state)
  assert.equal(unknown.purge, false)
})

test("cache names: exactly avoid-lists and app-shell-v<N>", () => {
  assert.equal(policy.AVOID_LISTS_CACHE, "avoid-lists")
  assert.equal(policy.shellCacheName(42), "app-shell-v42")
  assert.equal(policy.isShellCache("app-shell-v42"), true)
  assert.equal(policy.isShellCache("avoid-lists"), false)
})
