// Page-side helpers for talking to the service worker. Never registers it:
// only the signed-in pwa controller does that.
import { AVOID_LISTS_CACHE, CACHED_AT_HEADER } from "pwa/cache_policy"

export const SERVICE_WORKER_URL = "/service-worker.js"

export function supported() {
  return "serviceWorker" in navigator
}

// Sends a message and waits for the worker's reply, or null after `timeout` ms
// (or when there is no worker at all).
export async function postToWorker(message, { timeout = 1500, worker = null } = {}) {
  if (!supported()) return null
  let target = worker
  if (!target) {
    const registration = await navigator.serviceWorker.getRegistration("/")
    target = registration && (registration.active || registration.waiting || registration.installing)
  }
  if (!target) return null

  return new Promise((resolve) => {
    const channel = new MessageChannel()
    const timer = setTimeout(() => resolve(null), timeout)
    channel.port1.onmessage = (event) => {
      clearTimeout(timer)
      resolve(event.data)
    }
    target.postMessage(message, [ channel.port2 ])
  })
}

// Deletes the saved avoid lists straight from the page too, in case the
// worker is missing or slow.
export async function purgeLocally() {
  try {
    if ("caches" in window) await window.caches.delete(AVOID_LISTS_CACHE)
  } catch (_error) {
    // Storage blocked; nothing was saved.
  }
}

// Asks the worker to forget saved lists, waiting at most `timeout` ms.
// Never rejects: a missing or broken worker (or blocked storage) must not
// stop the nurse from signing out.
export async function purgeEverywhere(timeout = 1500) {
  const worker = Promise.resolve()
    .then(() => postToWorker({ type: "purge" }, { timeout }))
    .catch(() => null)
  await Promise.race([
    Promise.allSettled([ purgeLocally(), worker ]),
    new Promise((resolve) => setTimeout(resolve, timeout + 100))
  ])
}

// When the copy of `url` in avoid-lists was saved, or null.
export async function savedAt(url) {
  try {
    if (!("caches" in window) || !(await window.caches.has(AVOID_LISTS_CACHE))) return null
    const cache = await window.caches.open(AVOID_LISTS_CACHE)
    const response = await cache.match(url, { ignoreVary: true })
    return response ? response.headers.get(CACHED_AT_HEADER) : null
  } catch (_error) {
    return null
  }
}
