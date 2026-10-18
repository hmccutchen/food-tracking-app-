require "rails_helper"

RSpec.describe "Suggest meals", js: true do
  include ActiveJob::TestHelper

  after do
    SuggestMealsJob.adapter_factory = nil
    TaxonomyNode.delete_all
  end

  it "finds meals in the background, then marks them out of date and re-checks them" do
    Taxonomy::Seed.load!
    user = create(:user, active_provider: "openai")
    create(:provider_credential, user:, provider: "openai", model: "model-a")
    ana = user.patients.create!(display_name: "Ana Ruiz")
    ana.restrictions.create!(kind: :allergy, term: "shellfish")
    adapter = FakeMealAdapter.new(FakeMealAdapter.meals(
      FakeMealAdapter.meal("Shrimp rice", "shrimp", "rice"),
      FakeMealAdapter.meal("Mac and cheese", "macaroni", "cheddar cheese", prep_notes: [ "bake until bubbling" ])
    ))
    SuggestMealsJob.adapter_factory = ->(_credential) { adapter }

    sign_in(user)
    expect(page).to have_content("Signed in as")
    visit group_path(patient_ids: [ ana.id ])

    fill_in "What kind of meal?", with: "dinner for Ana Ruiz, soft foods"
    click_button "Suggest meals"
    expect(page).to have_content("Finding meals…")

    perform_enqueued_jobs
    expect(adapter.prompts.sole.text).not_to include("Ana Ruiz")

    # No websocket broadcast reaches the browser in tests: the 3s poll fallback does.
    using_wait_time(10) do
      expect(page).to have_no_content("Finding meals…")
      expect(page).to have_css(".meal-card h4", text: "Mac and cheese")
    end
    within(".meal-card", text: "Mac and cheese") do
      expect(page).to have_content("Suggested preparation (from OpenAI)")
      expect(page).to have_no_css('.tier-badge[data-tier="conflict"]')
    end
    expect(page).to have_content("Dropped (conflicts found)")
    find("summary", text: "Dropped (conflicts found)").click
    expect(page).to have_content(/shrimp is a shellfish.*\(allergy\)/)

    ana.restrictions.create!(kind: :allergy, term: "milk")
    visit group_path(patient_ids: [ ana.id ])
    expect(page).to have_content("Out of date — re-check")

    click_button "Re-check"
    within(".meal-card", text: "Mac and cheese") do
      expect(page).to have_content("Now a conflict")
      expect(page).to have_css('.tier-badge[data-tier="conflict"]')
    end
    expect(page).to have_no_content("Out of date — re-check")
    expect(adapter.calls).to eq(1)
  end
end
