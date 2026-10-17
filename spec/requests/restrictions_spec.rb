require "rails_helper"

RSpec.describe "Restrictions" do
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  let(:user) { create(:user) }
  let(:patient) { create(:patient, user:) }
  let(:stream) { { "Accept" => "text/vnd.turbo-stream.html" } }

  def node(name) = TaxonomyNode.find_by!(name:)

  before { sign_in(user) }

  describe "create" do
    it "adds a restriction via Turbo Stream with resolution feedback and the new version" do
      post patient_restrictions_path(patient), params: { restriction: { kind: "allergy", term: "almond flour" } },
        headers: stream
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('target="restrictions"').and include('target="profile_version"')
      expect(response.body).to include("alias &#39;almond flour&#39; → almond").and include("Profile v2")
      expect(patient.restrictions.sole).to have_attributes(taxonomy_node: node("almond"), match_type: "alias")
    end

    it "saves an unresolved term and says it was not recognized" do
      post patient_restrictions_path(patient), params: { restriction: { kind: "cannot", term: "grandma's stew" } },
        headers: stream
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("not recognized — will be checked by exact text only")
      expect(patient.restrictions.sole).to have_attributes(match_type: "unresolved", taxonomy_node: nil)
    end

    it "flags a fuzzy match for checking" do
      post patient_restrictions_path(patient), params: { restriction: { kind: "allergy", term: "almnd" } }, headers: stream
      expect(response.body).to include("fuzzy match to almond — please check")
    end

    it "stores a manual node choice" do
      post patient_restrictions_path(patient),
        params: { restriction: { kind: "allergy", term: "the seeds on bagels", manual_node_id: node("sesame").id } },
        headers: stream
      expect(response.body).to include("set by you")
      expect(patient.restrictions.sole).to have_attributes(taxonomy_node: node("sesame"), match_type: "manual")
    end

    it "re-renders the add form with errors" do
      post patient_restrictions_path(patient), params: { restriction: { kind: "allergy", term: "" } }, headers: stream
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('target="new_restriction"').and include("Term can")
      expect(patient.reload.profile_version).to eq(1)
    end

    it "redirects without Turbo" do
      post patient_restrictions_path(patient), params: { restriction: { kind: "allergy", term: "milk" } }
      expect(response).to redirect_to(patient)
    end
  end

  describe "update and destroy" do
    let!(:restriction) { create(:restriction, patient:, term: "milk") }

    it "renders the inline edit form in the row's frame" do
      get edit_patient_restriction_path(patient, restriction)
      expect(response.body).to include(%(<turbo-frame id="restriction_#{restriction.id}"))
    end

    it "updates via Turbo Stream, bumping the version once" do
      expect {
        patch patient_restriction_path(patient, restriction),
          params: { restriction: { kind: "intolerance", term: "lactose", note: "bloating" } }, headers: stream
      }.to change { patient.reload.profile_version }.by(1)
      expect(response.body).to include("Intolerances").and include("matched to lactose")
    end

    it "keeps a manual choice when only the note changes from the form" do
      restriction.update!(manual_node_id: node("egg").id)
      patch patient_restriction_path(patient, restriction),
        params: { restriction: { kind: "allergy", term: "milk", note: "new", manual_node_id: node("egg").id } },
        headers: stream
      expect(restriction.reload).to have_attributes(taxonomy_node: node("egg"), match_type: "manual", note: "new")
    end

    it "shows the edit form with errors when invalid" do
      patch patient_restriction_path(patient, restriction), params: { restriction: { term: "" } }, headers: stream
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Term can")
    end

    it "removes via Turbo Stream, bumping the version once" do
      expect {
        delete patient_restriction_path(patient, restriction), headers: stream
      }.to change { patient.reload.profile_version }.by(1)
      expect(Restriction.exists?(restriction.id)).to be(false)
      expect(response.body).to include("No restrictions yet")
    end
  end

  describe "another user's patient" do
    let(:other) { create(:patient) }
    let!(:theirs) { create(:restriction, patient: other) }

    it "returns 404 and changes nothing" do
      post patient_restrictions_path(other), params: { restriction: { kind: "allergy", term: "milk" } }
      expect(response).to have_http_status(:not_found)
      get edit_patient_restriction_path(other, theirs)
      expect(response).to have_http_status(:not_found)
      patch patient_restriction_path(other, theirs), params: { restriction: { term: "egg" } }
      expect(response).to have_http_status(:not_found)
      delete patient_restriction_path(other, theirs)
      expect(response).to have_http_status(:not_found)
      expect(theirs.reload.term).to eq("peanut")
    end

    it "returns 404 for their restriction under my patient" do
      get edit_patient_restriction_path(patient, theirs)
      expect(response).to have_http_status(:not_found)
    end
  end
end
