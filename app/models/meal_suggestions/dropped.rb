module MealSuggestions
  # A meal the engine found a conflict in, with what blocked it.
  Dropped = Data.define(:suggestion, :group_result, :blocking_ingredients, :reasons)
end
