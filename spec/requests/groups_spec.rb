require "rails_helper"

RSpec.describe "Groups (who's eating)" do
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  let(:user) { create(:user) }
  let!(:ana) { create(:patient, user:, display_name: "Ana Ruiz") }
  let!(:ben) { create(:patient, user:, display_name: "Ben Okafor") }
  let!(:stranger) { create(:patient, display_name: "Someone Else") }
  let(:turbo_stream) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  before do
    create(:restriction, patient: ana, kind: :allergy, term: "tree nuts")
    create(:restriction, patient: ben, kind: :condition, term: "low sodium")
    create(:restriction, patient: stranger, kind: :cannot, term: "secret term")
    sign_in(user)
  end

  it "requires sign-in" do
    sign_out
    get group_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "lists the nurse's patients to pick from, and nobody else's" do
    get group_path
    expect(response.body).to include("Who&#39;s eating?", "Ana Ruiz", "Ben Okafor", "avoid_list")
    expect(response.body).not_to include("Someone Else")
  end

  it "shows the merged avoid list for the selected patients" do
    get group_path(patient_ids: [ ana.id, ben.id ])
    expect(response.body).to include("tree nut", "includes almond", "sodium", "Avoid", "Limit")
    expect(response.body).to include("Check ingredients")
  end

  it "ignores another user's patient ids" do
    get group_path(patient_ids: [ ana.id, stranger.id ])
    expect(response.body).to include("tree nut")
    expect(response.body).not_to include("Someone Else")
    expect(response.body).not_to include("secret term")
    expect(session[:group_patient_ids]).to eq([ ana.id ])
  end

  it "remembers the last selection and sends the nurse back to it" do
    get group_path(patient_ids: [ ben.id ])
    get group_path
    expect(response).to redirect_to(group_path(patient_ids: [ ben.id ]))
    follow_redirect!
    expect(response.body).to include("sodium")
  end

  it "remembers clearing every box as nobody" do
    get group_path(patient_ids: [ ben.id ])
    get group_path(patient_ids: [ "" ])
    get group_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Pick at least one patient")
  end

  describe "checking ingredients" do
    it "returns a turbo stream with the tiers and reasons" do
      post check_group_path, params: { patient_ids: [ ana.id, ben.id ], ingredients: "almond flour, soy sauce" },
        headers: turbo_stream
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('<turbo-stream action="update" target="evaluation_result">')
      expect(response.body).to include('data-tier="conflict"', "Conflict", "Possible conflict")
      expect(response.body).to include("almond flour is a tree nut (allergy)", "soy sauce is high in sodium (low sodium)")
      expect(response.body).to include("Ana Ruiz", "Ben Okafor")
    end

    it "accepts one ingredient per line" do
      post check_group_path, params: { patient_ids: [ ana.id ], ingredients: "rice\nalmond flour\n" }, headers: turbo_stream
      expect(response.body).to include("almond flour is a tree nut (allergy)")
    end

    it "says no flags found without claiming a guarantee" do
      post check_group_path, params: { patient_ids: [ ana.id ], ingredients: "egg" }, headers: turbo_stream
      expect(response.body).to include("No flags found — this isn&#39;t a guarantee")
    end

    it "only evaluates the nurse's own patients" do
      post check_group_path, params: { patient_ids: [ stranger.id ], ingredients: "secret term" }, headers: turbo_stream
      expect(response.body).not_to include("Someone Else", "secret term")
      expect(response.body).not_to include('data-tier="conflict"')
    end

    it "renders the page with the result when JavaScript is off" do
      post check_group_path, params: { patient_ids: [ ana.id ], ingredients: "almond flour" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Who&#39;s eating?", "almond flour is a tree nut (allergy)")
    end
  end
end
