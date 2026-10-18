require "rails_helper"

RSpec.describe "Custom items (not-found path)", js: true do
  it "goes from an unknown flag to a custom item, and a re-check shows the new tier" do
    Taxonomy::Seed.load!
    user = create(:user)
    ana = user.patients.create!(display_name: "Ana Ruiz")
    ana.restrictions.create!(kind: :allergy, term: "milk")
    sign_in(user)
    expect(page).to have_content("Signed in as")

    visit group_path(patient_ids: [ ana.id ])
    fill_in "Ingredients (one per line, or separated by commas)", with: "Mrs. P's soup"
    click_button "Check"
    within("#evaluation_result") do
      expect(page).to have_css('.tier-badge[data-tier="unknown"]')
      click_link "Add as custom item"
    end

    expect(page).to have_content("Add a custom item")
    expect(page).to have_field("Name", with: "Mrs. P's soup")
    fill_in "Ingredients (optional, as on the label)", with: "contains wheat flour, milk"
    select "stock", from: "This is a kind of… (optional)"
    click_button "Add custom item"

    expect(page).to have_content("Custom item: mrs p's soup")
    within("#covered_by") { expect(page).to have_content("milk") }
    choose "mark_cannot_patient_#{ana.id}"
    click_button "Save"
    expect(page).to have_content("Saved who can and cannot have it.")

    visit group_path(patient_ids: [ ana.id ])
    fill_in "Ingredients (one per line, or separated by commas)", with: "Mrs. P's soup"
    click_button "Check"
    within("#evaluation_result") do
      expect(page).to have_css('.tier-badge[data-tier="conflict"]', text: "Conflict")
      expect(page).to have_content("Mrs. P's soup is in the milk group (allergy)")
      expect(page).to have_content("you marked Mrs. P's soup as cannot")
      expect(page).to have_no_link("Add as custom item")
    end
  end
end
