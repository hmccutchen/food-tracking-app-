# Evaluation rules

The evaluation engine (`app/models/evaluation/`) is plain Ruby. It takes the selected
patients and a list of ingredient strings and returns a result per patient plus a group
result. Code sets every tier. The AI never does.

## Tiers

Ordered from worst to mildest:

1. `conflict`: a known match against something the patient must avoid.
2. `possible_conflict`: a likely or uncertain match.
3. `unknown`: we can't tell.
4. no flag: nothing matched. The UI says **"No flags found — this isn't a guarantee"**,
   never "safe".

There are no scores or percentages. Every flag carries a reason a nurse can read.

## Per-ingredient, per-patient rules

Each ingredient is resolved with `Taxonomy::Resolver`. Then each of the patient's
restrictions is checked against it.

| Situation | Tier | Example reason |
|---|---|---|
| `allergy` restriction covers the ingredient (exact/alias/manual match) | conflict | "almond flour is a tree nut (allergy)" |
| `cannot` restriction covers the ingredient | conflict | "you marked shrimp as cannot" |
| `intolerance` restriction covers the ingredient | conflict | "whey contains milk (lactose intolerance)" |
| `condition` restriction covers the ingredient | possible_conflict | "soy sauce is high in sodium (low sodium)" |
| Any restriction covers the ingredient, but the ingredient was a **fuzzy** match | possible_conflict | "fuzzy match to almond — check the label" |
| Ingredient is in the ambiguous group (natural flavors, spices, stock…) and the patient has any allergy, intolerance or cannot | possible_conflict | "'natural flavors' listed — may hide allergens" |
| Ingredient is **unresolved** | unknown | "'xyz' not recognized" |
| The dish has **no ingredient list** | unknown | "no ingredient list found" |

A restriction whose own term was unresolved (no taxonomy node) falls back to text
matching. The normalized restriction term is compared against the normalized ingredient
as a whole word or phrase. A match counts as a conflict for allergy, intolerance and
cannot, and as a possible_conflict for a condition, with the reason "text match to
'<term>'".

## Overrides and precedence

- **"Cannot" always wins.** If a `can` and a `cannot` both cover an ingredient, the
  `cannot` applies.
- **A `can` never silences an allergy.** The allergy conflict stays, and the
  `can` is shown alongside it as "you marked this OK".
- A `can` covering an ingredient *does* clear intolerance, condition, fuzzy and
  ambiguous flags for that patient. A cleared flag is kept in the result as an
  overridden note ("you marked this OK"), so it stays visible and is never dropped
  silently.
- A `can` never clears `unknown`. An unrecognized ingredient is still unrecognized.

## Rolling up

- A patient's tier is the worst tier among their unoverridden flags.
- **Worst case wins:** the group tier is the worst tier among the patients. It is never
  softer than any one patient's tier.
- Every result records `profile_versions: { patient_id => version }`. A result is
  `stale?` when any patient's current `profile_version` differs from what was recorded.

## Things that can never change a tier

- Prep notes and the cross-contact reminder. They're advisory only.
- AI output. It supplies ingredient lists, nothing else.
