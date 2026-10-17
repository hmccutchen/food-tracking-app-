require "rails_helper"

RSpec.describe "Check ingredients with preparation notes" do
  before(:context) { load_prep_method_seed! }
  after(:context) { clear_prep_method_seed! }

  let(:user) { create(:user) }
  let!(:ana) { create(:patient, user:, display_name: "Ana Ruiz") }
  let!(:ben) { create(:patient, user:, display_name: "Ben Okafor") }
  let(:turbo_stream) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  before do
    create(:restriction, patient: ana, kind: :allergy, term: "shellfish")
    create(:restriction, patient: ben, kind: :condition, term: "low sodium")
    sign_in(user)
  end

  it "shows prep notes from the ingredients and the cross-contact line under the tier" do
    post check_group_path, params: { patient_ids: [ ana.id, ben.id ], ingredients: "tempura shrimp\nchicken broth" },
      headers: turbo_stream
    body = response.body
    expect(body).to include("Preparation note (advisory)", "frying", "stock or broth",
      "Lower-risk method: bake or pan-sear in fresh oil — still check shared pans and utensils",
      "Check shared pans, oil, and cutting boards", 'data-controller="dismiss"')
    expect(body.index("Overall:")).to be < body.index("Preparation note (advisory)")
    expect(body).to include('data-tier="conflict"')
  end

  it "shows no notes or reminder when nothing relevant applies" do
    post check_group_path, params: { patient_ids: [ ben.id ], ingredients: "tempura shrimp" }
    expect(response.body).not_to include("Preparation note (advisory)", "Check shared pans")
  end

  it "keeps prep notes off the tier: same result with the methods turned off" do
    params = { patient_ids: [ ana.id, ben.id ], ingredients: "tempura shrimp, chicken broth" }
    post check_group_path, params:, headers: turbo_stream
    with = response.body[/<div class="evaluation-result".*?<\/p>/m]
    PrepMethod.update_all(active: false)
    post check_group_path, params:, headers: turbo_stream
    expect(response.body).not_to include("Preparation note (advisory)")
    expect(response.body[/<div class="evaluation-result".*?<\/p>/m]).to eq(with)
  end
end
