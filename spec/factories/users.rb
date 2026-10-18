FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "nurse#{n}@example.com" }
    password { "password123" }
  end
end
