require "rails_helper"

RSpec.describe "Preparation notes page" do
  before(:context) { load_prep_method_seed! }
  after(:context) { clear_prep_method_seed! }

  let(:user) { create(:user) }
  let(:frying) { PrepMethod.find_by!(name: "frying") }

  before { sign_in(user) }

  it "requires sign-in" do
    sign_out
    get prep_methods_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "lists every method with its keywords, risks and lower-risk line" do
    get prep_methods_path
    expect(response.body).to include("Preparation notes", "frying", "tempura", "shellfish", "grilling",
      "Lower-risk method: bake or pan-sear in fresh oil — still check shared pans and utensils")
  end

  it "shows the edit form with the risk nodes preselected" do
    get edit_prep_method_path(frying)
    expect(response.body).to include("Lower-risk method", "Caveat", "Show this note")
    shellfish = TaxonomyNode.find_by!(name: "shellfish")
    expect(response.body).to match(/<option selected="selected" value="#{shellfish.id}">shellfish/)
  end

  it "updates keywords, texts, risk nodes and the active flag" do
    egg = TaxonomyNode.find_by!(name: "egg")
    patch prep_method_path(frying), params: { prep_method: {
      name: "frying", keywords_text: "fried, fryer", risk: "Shared oil.", lower_risk_method: "roast",
      caveat: "still check the tray", active: "0", risk_node_ids: [ "", egg.id.to_s ]
    } }
    expect(response).to redirect_to(prep_methods_path)
    frying.reload
    expect(frying).to have_attributes(keywords: %w[fried fryer], risk: "Shared oil.", lower_risk_method: "roast",
      caveat: "still check the tray", active: false)
    expect(frying.risk_nodes).to eq([ egg ])
  end

  it "rejects a missing caveat and leaves the risk nodes as they were" do
    before_ids = frying.risk_node_ids.sort
    patch prep_method_path(frying), params: { prep_method: { caveat: "", risk_node_ids: [ "" ] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Caveat can&#39;t be blank")
    expect(frying.reload.risk_node_ids.sort).to eq(before_ids)
  end
end
