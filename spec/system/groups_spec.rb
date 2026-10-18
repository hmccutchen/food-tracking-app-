require "rails_helper"

RSpec.describe "Who's eating", js: true do
  it "updates the merged avoid list as patients are ticked and checks ingredients" do
    Taxonomy::Seed.load!
    user = create(:user)
    ana = user.patients.create!(display_name: "Ana Ruiz")
    ben = user.patients.create!(display_name: "Ben Okafor")
    user.patients.create!(display_name: "Cy Park")
    ana.restrictions.create!(kind: :allergy, term: "tree nuts")
    ben.restrictions.create!(kind: :allergy, term: "nuts")
    ben.restrictions.create!(kind: :condition, term: "low sodium")
    sign_in(user)
    expect(page).to have_content("Signed in as")

    click_link "Who's eating"
    expect(page).to have_content("Pick at least one patient")
    expect(page).to have_no_button("Update")
    page.execute_script("window.__noReload = true")

    check "Ana Ruiz"
    within("#avoid_section_avoid") { expect(page).to have_content("tree nut").and have_content("Ana Ruiz") }
    check "Ben Okafor"
    within("#avoid_section_avoid") do
      expect(page).to have_css(".avoid-entry", count: 1)
      expect(page).to have_content("Ben Okafor")
    end
    within("#avoid_section_limit") { expect(page).to have_content("sodium") }
    expect(page).to have_current_path(/patient_ids/)

    fill_in "Ingredients", with: "almond flour, soy sauce"
    click_button "Check"

    within("#evaluation_result") do
      expect(page).to have_css('.tier-badge[data-tier="conflict"]', text: "Conflict")
      expect(page).to have_content("almond flour is a tree nut (allergy)")
      expect(page).to have_content("soy sauce is high in sodium (low sodium)")
    end
    expect(page.evaluate_script("window.__noReload")).to be(true)
  end
end
