FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "nurse#{n}@example.com" }
    password { "correct-horse-battery" }
  end
end
