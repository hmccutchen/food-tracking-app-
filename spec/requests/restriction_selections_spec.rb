require "rails_helper"

RSpec.describe "Choosing several restrictions at once" do
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  let(:user) { create(:user) }
  let(:patient) { create(:patient, user:) }

  def node(name) = TaxonomyNode.find_by!(name:)

  def save_list(target, kind, node_ids, version: target.reload.profile_version)
    patch patient_restriction_selection_path(target, kind), params: { node_ids:, profile_version: version }
  end

  # What the browser would send back for the page as rendered.
  def resubmit_unchanged(kind)
    get edit_patient_restriction_selection_path(patient, kind)
    page = Nokogiri::HTML(response.body)
    ticked = page.css("input[name='node_ids[]'][checked]").map { |box| box["value"] }
    save_list(patient, kind, [ "" ] + ticked, version: page.at_css("input[name=profile_version]")["value"])
  end

  before { sign_in(user) }

  it "links each kind on the patient page to its checklist, even when empty" do
    get patient_path(patient)
    Restriction.kinds.each_key do |kind|
      expect(response.body).to include(%(href="#{edit_patient_restriction_selection_path(patient, kind)}"))
    end
    expect(response.body).to include("None.")
  end

  it "shows the checklist with current items ticked and typed-only terms listed" do
    patient.restrictions.create!(kind: "allergy", term: "almond")
    patient.restrictions.create!(kind: "allergy", term: "grandma's stew")
    get edit_patient_restriction_selection_path(patient, "allergy")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Allergies for #{patient.display_name}", "Find an item", "1 item ticked")
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("#node_#{node("almond").id}")["checked"]).to eq("checked")
    expect(page.at_css("#node_#{node("milk").id}")["checked"]).to be_nil
    expect(response.body).to include("Also on this list (typed, not recognized)", "grandma&#39;s stew")
  end

  it "saves the ticked set and says what changed" do
    patient.restrictions.create!(kind: "allergy", term: "almond")
    save_list(patient, "allergy", [ "", node("milk").id, node("egg").id ])
    expect(response).to redirect_to(patient_path(patient))
    expect(flash[:notice]).to eq("Allergies: added egg and milk; removed almond.")
    expect(patient.restrictions.allergy.map(&:term)).to contain_exactly("milk", "egg")
  end

  it "clears the kind when everything is unticked (only the blank placeholder is sent)" do
    patient.restrictions.create!(kind: "cannot", term: "shrimp")
    save_list(patient, "cannot", [ "" ])
    expect(flash[:notice]).to eq("Cannot have: removed shrimp.")
    expect(patient.restrictions.reload).to be_empty
  end

  it "keeps everything on an unchanged save, even a match to the 'common food' umbrella with a note" do
    patient.restrictions.create!(kind: "cannot", term: "anything common", manual_node_id: node("common food").id,
      note: "only for now")
    patient.restrictions.create!(kind: "cannot", term: "shrimp", note: "hives")
    resubmit_unchanged("cannot")
    expect(flash[:notice]).to eq("Cannot have: no changes.")
    expect(patient.restrictions.reload.map { |r| [ r.term, r.note ] })
      .to contain_exactly([ "anything common", "only for now" ], [ "shrimp", "hives" ])
  end

  it "refuses a save from a page that is out of date, and shows the latest list" do
    get edit_patient_restriction_selection_path(patient, "allergy")
    old_version = patient.reload.profile_version
    patient.restrictions.create!(kind: "allergy", term: "egg") # saved from another window
    save_list(patient, "allergy", [ "", node("milk").id ], version: old_version)
    expect(response).to have_http_status(:conflict)
    expect(response.body).to include("profile changed in another window. Nothing was saved.")
    expect(Nokogiri::HTML(response.body).at_css("#node_#{node("egg").id}")["checked"]).to eq("checked")
    expect(patient.restrictions.reload.map(&:term)).to eq([ "egg" ])
  end

  it "sums up a long change as counts, so the notice fits in the session cookie" do
    all_ids = TaxonomyNode.pluck(:id)
    save_list(patient, "can", [ "" ] + all_ids)
    expect(response).to redirect_to(patient_path(patient))
    expect(flash[:notice]).to eq("Can have: added #{all_ids.size} items.")
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "shows a nested group's items inside it on the page" do
    get edit_patient_restriction_selection_path(patient, "allergy")
    cheese_item = Nokogiri::HTML(response.body).at_css("#node_#{node("cheese").id}").ancestors("li").first
    nested = cheese_item.css("ul input[name='node_ids[]']").map { |box| box["value"].to_i }
    expect(nested).to include(node("parmesan").id)
    expect(nested).not_to include(node("cream").id)
  end

  it "says which foods listed elsewhere a group also covers" do
    get edit_patient_restriction_selection_path(patient, "can")
    expect(response.body).to include("also covers oat and soy sauce (listed elsewhere)")
    expect(response.body).to include("Unticking an item inside a ticked group doesn't take it out of that group.")
  end

  it "warns on the Can have list that it never hides an allergy" do
    get edit_patient_restriction_selection_path(patient, "can")
    expect(response.body).to include("Can have for", "never hides an allergy")
  end

  it "only reaches the nurse's own patients and real kinds" do
    other = create(:patient)
    get edit_patient_restriction_selection_path(other, "allergy")
    expect(response).to have_http_status(:not_found)
    get edit_patient_restriction_selection_path(patient, "maybe")
    expect(response).to have_http_status(:not_found)
    save_list(other, "allergy", [ node("egg").id ])
    expect(other.restrictions).to be_empty
  end

  it "explains 'Match automatically' on the single-item form" do
    get patient_path(patient)
    expect(response.body).to include(%("Match automatically" looks up what you typed))
  end
end
