require "rails_helper"

RSpec.describe "Preparation notes on a checked meal", js: true do
  after { clear_prep_method_seed! }

  it "shows an advisory note that the nurse can dismiss, and remembers it" do
    load_prep_method_seed!
    user = create(:user)
    ana = user.patients.create!(display_name: "Ana Ruiz")
    ana.restrictions.create!(kind: :allergy, term: "shellfish")
    sign_in(user)
    expect(page).to have_content("Signed in as")

    visit group_path(patient_ids: [ ana.id ])
    fill_in "Ingredients (one per line, or separated by commas)", with: "tempura shrimp"
    click_button "Check"

    within("#evaluation_result") do
      expect(page).to have_css('.tier-badge[data-tier="conflict"]')
      expect(page).to have_content("Check shared pans, oil, and cutting boards")
      expect(page).to have_content("Preparation note (advisory): frying")
      click_button "Dismiss note"
      expect(page).to have_no_content("Preparation note (advisory)")
      expect(page).to have_content("Check shared pans, oil, and cutting boards")
    end

    stored = page.evaluate_script("window.localStorage.getItem('dismissed-prep-notes')")
    expect(JSON.parse(stored)).to contain_exactly(match(/\Aprep-\d+-\h{16}\z/))

    # A fresh result with the same note stays dismissed.
    fill_in "Ingredients (one per line, or separated by commas)", with: "tempura shrimp, zzqx"
    click_button "Check"
    within("#evaluation_result") do
      expect(page).to have_content("'zzqx' not recognized")
      expect(page).to have_css(".prep-note", visible: :hidden)
      expect(page).to have_no_content("Preparation note (advisory)")
    end
  end
end
