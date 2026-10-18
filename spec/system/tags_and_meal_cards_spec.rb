require "rails_helper"

RSpec.describe "Tag inputs and removable meal cards", js: true do
  after { TaxonomyNode.delete_all }

  it "turns comma-separated entries into removable tags and saves them" do
    Taxonomy::Seed.load!
    user = create(:user)
    sign_in(user)
    expect(page).to have_content("Signed in as")
    visit new_custom_item_path

    fill_in "Name", with: "Granny's soup"
    fill_in "Other names (optional)", with: "granny soup, sunday soup"
    expect(page).to have_css(".tag", text: "granny soup")
    find_field("Other names (optional)").send_keys("tuesday soup", :enter)
    expect(page).to have_css(".tag", text: "sunday soup").and have_css(".tag", text: "tuesday soup")
    find("button[aria-label='Remove sunday soup']").click
    expect(page).to have_no_css(".tag", text: "sunday soup")

    # A label pasted in one go: commas inside brackets stay with their item.
    fill_in "Ingredients (optional, as on the label)", with: "wheat flour (enriched, niacin), salt, "
    expect(page).to have_css(".tag", text: "wheat flour (enriched, niacin)").and have_css(".tag", text: "salt")

    click_button "Add custom item"
    expect(page).to have_content("Custom item added.")
    node = TaxonomyNode.find_by!(name: "granny's soup")
    expect(node.aliases.pluck(:term)).to contain_exactly("granny soup", "tuesday soup")
    expect(node.ingredients_text).to eq("wheat flour (enriched, niacin), salt")
  end

  it "removes a finished meal card from the page without a reload" do
    user = create(:user)
    patient = user.patients.create!(display_name: "Ana Ruiz")
    request = create(:meal_request, user:, patient_ids: [ patient.id ], status: "found")
    create(:meal_suggestion, meal_request: request, dish: "Lentil soup")

    sign_in(user)
    expect(page).to have_content("Signed in as")
    visit group_path(patient_ids: [ patient.id ])
    expect(page).to have_css(".meal-card h4", text: "Lentil soup")
    page.execute_script("window.__noReload = true")

    find("form.remove-meal-request button").click
    expect(page).to have_no_css(".meal-card h4", text: "Lentil soup")
    expect(page).to have_content("No meal suggestions yet.")
    expect(page.evaluate_script("window.__noReload")).to be(true)
    expect(MealRequest.exists?(request.id)).to be(false)
  end
end
