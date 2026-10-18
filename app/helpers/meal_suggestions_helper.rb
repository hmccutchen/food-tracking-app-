module MealSuggestionsHelper
  # AI-written text (dish names, prep notes) is shown as is, except that the
  # nurse is never told something is "safe": that word is the AI's, not ours.
  AI_WORDING = { /\bsafely\b/i => "carefully", /\bsafe\b/i => "lower-risk" }.freeze

  def ai_text(text)
    AI_WORDING.reduce(text.to_s) { |out, (pattern, replacement)| out.gsub(pattern, replacement) }
  end

  # Advisory only, recomputed for display from the stored dish and
  # ingredients; never stored, never part of the tier.
  def meal_prep_notes(suggestion, patient_ids)
    PrepNotes.for(patients: patient_ids, dish: suggestion.dish, ingredients: suggestion.ingredients,
      prep_notes: suggestion.prep_notes)
  end
end
