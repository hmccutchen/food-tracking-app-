require "rails_helper"

RSpec.describe "Managing patients" do
  before do
    Taxonomy::Seed.load!
    sign_in(create(:user))
  end

  it "adds a patient and a restriction" do
    click_link "Patients"
    click_link "Add a patient"
    fill_in "Name", with: "Rosa Diaz"
    fill_in "Notes", with: "Lives alone"
    click_button "Create Patient"

    expect(page).to have_css("h1", text: "Rosa Diaz")
    expect(page).to have_content("Profile v1")

    select "Allergy", from: "Kind"
    fill_in "What (in your words)", with: "almond flour"
    fill_in "Note (optional)", with: "carries an EpiPen"
    click_button "Add restriction"

    within "#restrictions_allergy" do
      expect(page).to have_content("almond flour")
      expect(page).to have_content("alias 'almond flour' → almond")
      expect(page).to have_content("carries an EpiPen")
    end
    expect(page).to have_content("Profile v2")

    select "Cannot have", from: "Kind"
    fill_in "What (in your words)", with: "qwrtp"
    click_button "Add restriction"

    within "#restrictions_cannot" do
      expect(page).to have_content("not recognized — will be checked by exact text only")
    end
    expect(page).to have_content("Profile v3")
  end
end

RSpec.describe "Managing restrictions in the browser", js: true do
  it "adds and removes a restriction through Turbo Streams without a reload" do
    Taxonomy::Seed.load!
    user = create(:user)
    patient = user.patients.create!(display_name: "Sam Lee")
    sign_in(user)
    expect(page).to have_content("Patients")

    visit patient_path(patient)
    page.execute_script("window.__noReload = true")

    select "Intolerance", from: "Kind"
    fill_in "What (in your words)", with: "lactose"
    click_button "Add restriction"

    within("#restrictions_intolerance") { expect(page).to have_content("lactose") }
    expect(page).to have_content("Profile v2")
    expect(page.evaluate_script("window.__noReload")).to be(true)
  end
end

RSpec.describe "Choosing several restrictions at once in the browser", js: true do
  it "filters the checklist, counts ticks and saves the set" do
    Taxonomy::Seed.load!
    user = create(:user)
    patient = user.patients.create!(display_name: "Sam Lee")
    sign_in(user)
    expect(page).to have_content("Patients")

    visit patient_path(patient)
    within("#restrictions_allergy") { click_link "Choose items" }
    expect(page).to have_content("Allergies for Sam Lee")

    fill_in "Find an item", with: "almo"
    expect(page).to have_field("almond", visible: true)
    expect(page).to have_no_field("milk", visible: true)
    expect(page).to have_no_field("salmon", visible: true) # matches from the start of a word only
    check "almond"
    expect(page).to have_content("1 item ticked")

    # A hyphen in the search matches the space in the name, as it would on a label.
    fill_in "Find an item", with: "sesame-oil"
    expect(page).to have_field("sesame oil", visible: true)

    fill_in "Find an item", with: "zzzz"
    expect(page).to have_content("Nothing on the list matches")
    fill_in "Find an item", with: ""
    check "node_#{TaxonomyNode.find_by!(name: "milk").id}" # "milk" alone also matches "buttermilk"
    expect(page).to have_content("2 items ticked")

    first(:button, "Save list").click
    expect(page).to have_content("Allergies: added almond and milk.")
    within("#restrictions_allergy") { expect(page).to have_content("almond").and have_content("milk") }
  ensure
    TaxonomyNode.delete_all
  end
end
