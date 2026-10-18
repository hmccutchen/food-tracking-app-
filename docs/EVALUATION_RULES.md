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
| Ingredient is a **fuzzy** match and the phrase scan found nothing known inside it | unknown | "'peanutt' only loosely matches peanut — check the label" |
| Ingredient is unresolved or fuzzy, the scan found something, but some other word is not a descriptor | unknown | "'breaded chicken breast' not recognized (not recognized: 'breaded')" |
| Ingredient is unresolved or fuzzy, and every word is part of a scan match, an active descriptor or a number | no whole-phrase flag (the matches are still checked) | "2 cups diced chicken breast" → chicken |
| The dish has **no ingredient list** | unknown | "no ingredient list found" |

### Phrases that contain a known ingredient

AI and recipe ingredients are usually phrases ("roasted almonds", "egg noodles",
"low-sodium soy sauce"). If the whole phrase resolves by exact, alias or manual match,
that node alone is used. "Almond milk" is an alias of almond, so it is not milk.

Otherwise, when the phrase is fuzzy or unresolved, the phrase is also **scanned** for
known names and aliases. The scan splits on spaces and hyphens, tries singular forms and
takes the longest matches first, without overlaps. That way "peanut butter cookies"
finds peanut and not butter. Each node it finds is checked like a directly listed
ingredient, at that restriction kind's normal tier. The reason reads "'soy sauce'
appears in 'low-sodium soy sauce'". The fuzzy and unknown flags for the whole phrase
are kept as well, unless every other word is a descriptor (see below). A false positive
such as "cream of tartar" (cream → milk) is acceptable, because worst case wins. The fix
for one is to add an alias, never to loosen the scan ("butter lettuce" is an alias of
lettuce for that reason).

### Descriptor words

Most AI ingredients are a known food plus harmless modifiers: "2 cups cooked brown rice",
"diced chicken breast", "extra-virgin olive oil". The nurse keeps a list of **descriptor
words** (the "Descriptor words" page, linked from Preparation notes; defaults in
`db/seeds/ingredient_descriptors.rb`). A fuzzy or unresolved phrase drops its whole-phrase
unknown flag **only** when the scan found at least one known ingredient and every other
word is an active descriptor or a number ("2", "½", "200g"). Any other leftover word
keeps the phrase unknown, and the reason names it. Descriptors never clear or lower a
flag raised by a match: "roasted almonds" is still a tree nut conflict.

Descriptors must never change what is in the food or hide what it is. These can never
be added (the model refuses them): **breaded, battered, fried, crispy, glazed, marinated,
stuffed, seasoned, flavored, sauce, style, mix, blend, imitation, low-sodium**.
"Low-sodium" stays out because the scan already reads it as the sodium group. "Canned"
is not a default either (canned foods are often salted). Turning a word off makes
phrases that use it unknown again.

### Common foods

The taxonomy includes about 200 common single whole foods under `common food` (poultry,
meats, grains, legumes, vegetables, fruits, herbs and single spices, seeds, oils, a few
pantry items), so "chicken breast" or "blueberries" is recognized rather than unknown.
Recognized does not mean no flags: these nodes are checked like any other, and the
high-potassium ones are members of the potassium group. Mixed or processed items
(sauces, breads, noodles, pasta, sausages, seasoning blends, broth, dressing) are
deliberately absent and stay unknown. Allergen-related foods live under their allergen,
not here. **Oats** sit under common food but are a *member* of the gluten group because
cross-contact with wheat is common: a gluten restriction flags "oat milk" as a conflict
("oat milk is in the gluten group"), a wheat allergy does not. **Coconut** is a common
food (the FDA no longer lists it as a tree nut); a nurse can add a cannot.

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
