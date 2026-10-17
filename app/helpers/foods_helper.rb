module FoodsHelper
  # The food's taxonomy link in plain words. A fuzzy link always asks for a check.
  def food_link_summary(food)
    if food.fuzzy_link? && food.taxonomy_node
      safe_join([ tag.strong("Fuzzy match — please check."), " Might be #{food.taxonomy_node.name}: #{food.match_reason}" ])
    elsif food.linked? && food.taxonomy_node
      "Ingredient link: #{food.match_reason}"
    else
      "Not linked to a known ingredient, so checks treat it as unknown"
    end
  end
end
