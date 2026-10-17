# Meal Planner — working notes

Rails 8.1 app for one home health nurse choosing meals for patients with food
restrictions. The full plan and milestone list live in `docs/PLAN.md`; read it before
starting a milestone.

## Environment
- Ruby lives at `/opt/rbenv/versions/3.3.6/bin`; put it on `PATH` first.
- Postgres 16 runs locally (`service postgresql start` if it's down). The DB role is `root`.
- Run specs with `bundle exec rspec`. Run the full CI with `bin/ci`.
- JS system specs (`js: true`) use Cuprite against the Chromium at
  `/opt/pw-browsers/chromium-1194/chrome-linux/chrome`.

## Rules that never bend
- The evaluation engine is plain Ruby under `app/models/evaluation/`. It makes no network
  calls and no AI calls. Code sets the tier; the AI never does.
- Tiers are `conflict`, `possible_conflict`, `unknown`. No percentages, no scores.
- An ingredient the resolver can't map is `unknown`, never a pass.
- A "cannot" always wins. A "can" never silences an allergy and stays visible as
  "you marked this OK". The group result is never softer than any patient's result.
- Every flag carries a human-readable reason.
- Never show the word "safe" to the nurse. Use "No flags found — this isn't a guarantee"
  or "lower-risk method".
- Prep notes are advisory; they can never lower or clear a tier.
- Patient names never go to an AI provider. Only restriction terms do.
- API keys are encrypted, never logged, never rendered (last 4 chars only), and never
  passed as job arguments. Jobs load them by user ID.
- No spec touches the network. WebMock blocks it; provider specs use VCR cassettes.

## Conventions
- RSpec + FactoryBot + shoulda-matchers. Specs go under `spec/` by type.
- Encrypted columns use Active Record Encryption (`encrypts`).
- Hotwire (Turbo + Stimulus) for UI. Keep views plain; no CSS framework.
- Keep `bin/rubocop` and `bin/brakeman` clean.
- One commit per milestone, message starting with the milestone ID (e.g. `M1: …`).
