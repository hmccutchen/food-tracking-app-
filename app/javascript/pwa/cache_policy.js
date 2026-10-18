// What the service worker may cache, and for how long. Pure functions with no
// browser globals, so the service worker imports this file and Node's test
// runner checks it (test/javascript/cache_policy.test.js).
//
// Two caches, nothing else:
//   app-shell-v<N>  compiled CSS/JS, icons, the offline page. No patient data.
//   avoid-lists     the HTML of up to 5 recent GET /group pages, 24 hours each.

export const AVOID_LISTS_CACHE = "avoid-lists"
export const SHELL_CACHE_PREFIX = "app-shell-v"
export const MAX_AVOID_LISTS = 5
export const MAX_AGE_MS = 24 * 60 * 60 * 1000
export const CACHED_AT_HEADER = "X-Cached-At"
export const OFFLINE_URL = "/offline.html"
export const SIGN_IN_PATH = "/session/new"
const AVOID_LIST_PATH = "/group"

export function shellCacheName(version) {
  return `${SHELL_CACHE_PREFIX}${version}`
}

export function isShellCache(name) {
  return typeof name === "string" && name.startsWith(SHELL_CACHE_PREFIX)
}

// Only the avoid-list page itself: same origin, GET, exactly /group (the
// query string carries the selection). Everything else is network-only.
export function isCacheableRequest(url, method, origin) {
  if (String(method).toUpperCase() !== "GET") return false
  const parsed = parseUrl(url)
  if (!parsed) return false
  if (origin !== undefined && parsed.origin !== origin) return false
  return parsed.pathname === AVOID_LIST_PATH
}

// A response worth keeping: a plain 200 HTML page that was not bounced to
// sign-in. 401/403, redirects and opaque responses are never stored.
export function isCacheableResponse(response) {
  if (!response || response.status !== 200) return false
  if (response.type && response.type !== "basic" && response.type !== "default") return false
  if (shouldPurgeFor(response)) return false
  const finalUrl = parseUrl(response.url)
  if (finalUrl && finalUrl.pathname !== AVOID_LIST_PATH) return false
  const type = headerValue(response.headers, "content-type") || ""
  return type.includes("text/html")
}

// True when a response shows the session is gone: a 401, or a fetch that
// ended up on the sign-in page (followed redirect, or a direct load of it).
export function shouldPurgeFor(response, requestUrl) {
  if (!response) return false
  if (response.status === 401) return true
  const finalUrl = parseUrl(response.url)
  if (response.redirected && finalUrl && finalUrl.pathname === SIGN_IN_PATH) return true
  const requested = parseUrl(requestUrl)
  return Boolean(requested && requested.pathname === SIGN_IN_PATH)
}

// cachedAt: milliseconds, an ISO string, or a missing header. Anything we
// cannot read as a time counts as expired, so it is never served.
export function isExpired(cachedAt, now = Date.now()) {
  const time = toMillis(cachedAt)
  if (time === null) return true
  if (time > now + 60 * 1000) return true
  return now - time >= MAX_AGE_MS
}

// entries: [{ url, cachedAt }]. Returns the newest `max`, newest first.
export function trimToNewest(entries, max = MAX_AVOID_LISTS) {
  return [ ...entries ]
    .sort((a, b) => (toMillis(b.cachedAt) ?? -Infinity) - (toMillis(a.cachedAt) ?? -Infinity))
    .slice(0, Math.max(0, max))
}

// The urls a sweep removes: every expired entry, then the oldest beyond `max`.
export function entriesToDelete(entries, now = Date.now(), max = MAX_AVOID_LISTS) {
  const fresh = entries.filter((entry) => !isExpired(entry.cachedAt, now))
  const keep = new Set(trimToNewest(fresh, max).map((entry) => entry.url))
  return entries.filter((entry) => !keep.has(entry.url)).map((entry) => entry.url)
}

// What the service worker does with a message from a page.
// Returns the new state plus whether avoid-lists must be deleted.
export function applyMessage(state, message) {
  const type = message && message.type
  if (type === "session") {
    const signedIn = message.signedIn === true
    const offlineCaching = signedIn && message.offlineCaching === true
    return { state: { signedIn, offlineCaching }, purge: !offlineCaching }
  }
  if (type === "purge") return { state: { signedIn: false, offlineCaching: false }, purge: true }
  return { state, purge: false }
}

export function initialState() {
  return { signedIn: false, offlineCaching: false }
}

export function mayCache(state) {
  return Boolean(state && state.signedIn && state.offlineCaching)
}

function parseUrl(url) {
  if (!url) return null
  try {
    return new URL(url)
  } catch (_error) {
    return null
  }
}

function toMillis(value) {
  if (value === null || value === undefined || value === "") return null
  const time = typeof value === "number" ? value : Date.parse(value)
  return Number.isFinite(time) ? time : null
}

function headerValue(headers, name) {
  if (!headers) return null
  if (typeof headers.get === "function") return headers.get(name)
  const key = Object.keys(headers).find((candidate) => candidate.toLowerCase() === name)
  return key ? headers[key] : null
}
