FactoryBot.define do
  factory :taxonomy_node do
    sequence(:name) { |n| "ingredient #{n}" }
    kind { :ingredient }
  end

  factory :taxonomy_alias do
    taxonomy_node
    sequence(:term) { |n| "alias #{n}" }
  end
end
