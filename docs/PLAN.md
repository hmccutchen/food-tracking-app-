# Meal Planner for Home Health Nurse — v1 Plan

## 1. What we're building

A private web app (installable on a phone) for one nurse. She keeps a profile for each
patient listing what they can't eat: allergies, intolerances, conditions, and her own
"cannot" and "can" ingredients. Before a meal she picks who's eating, and the app shows
one combined avoid list for the group. She can search foods (USDA data plus our own
allergen mapping) or press a button to get AI meal ideas. Every suggestion is checked by
plain Ruby code, not the AI, and labeled **conflict**, **possible conflict**, or
**unknown**, with a short reason for each flag. Meal cards also show prep-method
cautions and a cross-contact reminder. She can override anything. The app warns her but
never blocks her. Medications and calendars are out of scope.

## 2. How the pieces connect

```
Nurse (browser / installed PWA)
  │  Turbo + Stimulus · service worker caches app shell + last avoid lists
  ▼
Rails controllers ── Rails auth (one user)
  │
  ├─ Patients & Restrictions ──► Taxonomy (nodes + aliases, pg_trgm)
  │      (encrypted fields, versioned)        ▲
  │                                           │ resolves terms
  ├─ Group view ──► AvoidList.build(patients) ┘
  │
  ├─ Food search ──► Foods (USDA Foundation + SR Legacy, imported by rake)
  │
  └─ "Suggest meals" ──► SuggestMealsJob (Solid Queue, loads key by user_id)
                            │
                            ├─► MealSuggester ──► Gemini | Anthropic | OpenAI adapter
                            │     (restriction terms only, no names → JSON → validate)
                            │
                            ├─► Evaluation::Engine  (pure Ruby, no network)
                            │     per-patient tier + reasons → worst-case rollup
                            │     stamped with profile versions
                            │
                            ├─► PrepNotes (DB risk table) + cross-contact line
                            │
                            └─► drop conflicts → retry ≤2 with rejected list
                                 → Turbo Stream meal cards (or "couldn't find…")
```

**Engine rules**
- **Unresolved means unknown.** If the resolver can't map an ingredient to a taxonomy
  node, that ingredient gets an `unknown` flag with a reason ("'xyz' not recognized"). It
  never counts as a pass.
- **When nothing is flagged**, the card says "No flags found" with the note "this isn't
  a guarantee — check labels". The app never uses the word "safe".
- Precedence: a "cannot" always wins. A "can" never silences an allergy and stays
  visible as "you marked this OK".
- Worst case wins: the group result is never softer than any one patient's result.
- Prep notes are advisory only and can never lower a tier.

## 3. Build order (each milestone runs and has green specs)

| # | Milestone | Done when |
|---|-----------|-----------|
| M0 | **Skeleton.** Rails 8 + Postgres + RSpec + Solid Queue, built-in auth, pg_trgm enabled, AR Encryption keys set up, CI script | Nurse can sign in; `bin/rspec` passes |
| M1 | **Taxonomy.** `taxonomy_nodes` (tree), `taxonomy_aliases`, seed for the top 9 allergens + common intolerances, plus a `Taxonomy::Resolver` that maps exact, alias, and fuzzy matches to a node, or returns an explicit `unresolved` result | Heavy specs: "no nuts", "tree nuts", and "almond flour" resolve to one node; fuzzy matches are marked fuzzy; gibberish comes back `unresolved`, never nil or a pass |
| M2 | **Patients & restrictions.** CRUD with encrypted fields, restriction kinds (allergen/intolerance/condition/cannot/can), profile `version` bumped on every change | Can add and edit patients in the UI; specs for the version bump and encryption |
| M3 | **Evaluation engine.** POROs: `Evaluation::Engine`, `PatientResult`, `GroupResult`, `Flag(tier, reason)`. Covers unresolved ingredients (→ `unknown`), missing ingredient lists, "natural flavors", fuzzy-match reasons, the "No flags found" outcome, and profile-version stamps plus `stale?` | Largest spec suite: precedence, multi-patient worst case, a "can" that doesn't override an allergy, unresolved never passes, stale detection |
| M4 | **Group avoid list.** Select patients → combined avoid list (Turbo), with each entry traced to the patient(s) who need it | Pick 3 patients and see one merged list |
| M5 | **USDA import.** `rake usda:import[path]` for Foundation + SR Legacy CSVs. Stores raw ingredient text, source, and imported_at; links foods to taxonomy nodes; trigram search UI | Import a sample fixture in specs; search for "almnd" and find almond |
| M6 | **Prep notes + cross-contact.** `prep_risks` table (method → risk nodes, caveat text), triggered by restrictions; dismissible on the card; cross-contact line for allergy patients | Specs prove notes never change a tier; "lower-risk method" wording, never "safe" |
| M7 | **AI settings (BYOK).** Provider picker with a privacy note, encrypted key, last-4 display only, test call on save, editable model name per provider, key filtered from logs | Save, validate, and mask a key; specs confirm the key never appears in logs or responses |
| M8 | **MealSuggester + adapters.** Provider-neutral prompt, JSON parse and validate into `{dish, ingredients[], prep_notes[]}`, malformed output counts as a failed attempt, errors mapped (invalid key / quota / rate limit / timeout → plain messages) | Recorded-response (VCR) spec per adapter, plus a failure spec for each |
| M9 | **Sample-request harness.** `rake meals:samples[provider]` runs a fixed request set (e.g. "dinner, no wheat, no dairy, low sodium") through suggester + engine, against one or all providers. It prints a table per provider: meals returned, how many were dropped as conflicts, `unknown` rate, and malformed or failed attempts | Runs against all 3 providers with real keys; filter rates are compared before the suggest flow is built |
| M10 | **Not-found path (custom items).** When a food or ingredient isn't in USDA or the taxonomy, the nurse adds a custom item (name, optional ingredient text, optional link to a taxonomy node) and marks it can/cannot per patient. Custom items feed the resolver, and each patient's can/cannot bumps that profile's version | Specs: an unresolved term becomes resolvable once added; a per-patient "cannot" on a custom item yields `conflict`; a "can" still never silences an allergy |
| M11 | **Suggest flow + staleness UI.** `SuggestMealsJob(user_id, …)` → evaluate → drop conflicts → retry ≤2 → Turbo Stream cards or a "couldn't find a meal" card listing what blocked it. A card whose stored profile versions no longer match is marked **"Out of date — re-check"** and has a re-evaluate button | End-to-end system spec with a stubbed suggester; spec that editing a patient flips their existing cards to out-of-date |
| M12 | **PWA.** Manifest, service worker, offline banner. Cached data includes restriction terms, so: cache only after sign-in, purge all caches on sign-out (and on a 401), no patient data in the manifest or the precache list. Avoid-list entries carry a cached-at timestamp; entries older than 24h are purged (checked on SW activate, on each fetch, and never served when expired). User setting `offline_caching_enabled` (default on): when off, the SW caches no patient data and deletes the `avoid-lists` cache immediately | Lighthouse "installable"; avoid list loads offline; tests that sign-out leaves caches empty, a 25h-old entry is purged and not served, and turning the setting off empties `avoid-lists` |

**What the PWA cache stores (M12), exactly:**
- `app-shell-v{n}`: layout HTML, compiled CSS and JS, icons, and the offline page. No
  patient data.
- `avoid-lists` (only when offline caching is on; each entry expires after 24 hours): the
  HTML of up to 5 most recently viewed group avoid-list pages. Each one
  holds patient display names, restriction terms, and source labels. No API keys, no
  meal results, nothing from the AI settings pages.
- Nothing else. Pages that change data are network-only, and so are the settings and
  sign-in pages.

## RubyLLM: should we use it?

**Yes, behind our own interface.** The gem is current and actively maintained. Version
2.1.1 shipped Oct 11, 2026; 2.0.0 came out Sep 18, 2026, after a run of release
candidates; and it has about 14M downloads. It covers Gemini, Anthropic, and OpenAI with
one API, which saves us from writing three HTTP clients.

How we'd use it:
- Pin `ruby_llm ~> 2.1`.
- `MealSuggester` and our three adapter classes stay ours. Each adapter is a thin wrapper
  that calls RubyLLM with that user's key and that provider's configured model, then maps
  RubyLLM's errors to our plain-language messages.
- Use a per-call context for keys, never global config, so one user's key can't leak
  into another call. We confirm this works early in M8.
- If 2.x causes trouble, we can swap in a plain HTTP adapter for one provider without
  touching the rest of the app.

## Verification
- `bin/rspec` stays green at every milestone. Taxonomy and the engine get the deepest
  coverage.
- `bin/dev` lets you try each milestone by hand in the browser.
- M9 harness for real-provider comparison.
