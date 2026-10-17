module MealSuggestions
  # A meal with no conflict. prep_notes and cross_contact are advisory only.
  Kept = Data.define(:suggestion, :group_result, :prep_notes, :cross_contact)
end
