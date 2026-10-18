module MealSuggestionsHelper
  # AI-written text (dish names, ingredients, prep notes, and flag reasons that
  # quote an ingredient) is shown as is, except that the nurse is never told
  # something is "safe": that word is the AI's, not ours. Display only: the
  # engine always evaluates the original ingredient text.
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
