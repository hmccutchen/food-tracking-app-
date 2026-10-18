# Default descriptor words (IngredientDescriptor). Loaded by Taxonomy::Seed.load!.
# Create-only: a word the nurse turned off stays off, and her own words are left
# alone. (The page turns words off rather than deleting them.)
#
# Only modifiers that never add an ingredient or hide one. Never add the words
# in IngredientDescriptor::NEVER (breaded, fried, marinated, seasoned, sauce,
# mix, blend, imitation, low-sodium...). "canned" is left out on purpose:
# canned foods are often salted. Numbers and fractions are handled in code.
module IngredientDescriptorSeedData
  WORDS = %w[
    fresh frozen raw cooked chopped diced minced sliced shredded grated cubed crushed
    boneless skinless lean large small medium whole ripe organic peeled halved quartered
    rinsed drained dried ground toasted roasted steamed boiled baked grilled
    unsalted unsweetened plain extra-virgin virgin light dark red green yellow white black baby
    cup cups tbsp tsp tablespoon tablespoons teaspoon teaspoons oz ounce ounces lb lbs pound pounds
    g grams kg ml can cans clove cloves pinch sprig sprigs leaf leaves bunch stalk stalks
    slice slices piece pieces of and or in with
  ].freeze

  module_function

  def load!
    existing = IngredientDescriptor.pluck(:word).to_set
    WORDS.each do |word|
      IngredientDescriptor.create!(word:) unless existing.include?(word)
    end
  end
end
