require "rails_helper"

RSpec.describe "Custom items" do
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  let(:user) { create(:user) }
  let!(:ana) { create(:patient, user:, display_name: "Ana Ruiz") }
  let(:stranger) { create(:user) }

  def node(name) = TaxonomyNode.find_by!(name:)

  def item_for(owner, **attributes)
    CustomItem.new(user: owner, **attributes).tap(&:save).node
  end

  before { sign_in(user) }

  it "requires sign-in" do
    delete session_path
    get custom_items_path
    expect(response).to redirect_to(new_session_path)
  end

  it "prefills the new form from the not-found links" do
    get new_custom_item_path(name: "Mrs. P's soup")
    expect(response.body).to include('value="Mrs. P&#39;s soup"', "This is a kind of")
  end

  it "creates an item and shows what covers it" do
    post custom_items_path, params: { custom_item: { name: "Mrs. P's soup", ingredients_text: "contains wheat flour, milk",
      parent_id: node("stock").id, aliases_text: "p soup" } }
    item = user.custom_items.sole
    expect(response).to redirect_to(custom_item_path(item))
    expect(item).to have_attributes(name: "mrs p's soup", parent: node("stock"), ingredients_text: "contains wheat flour, milk")

    follow_redirect!
    expect(response.body).to include("Custom item: mrs p&#39;s soup", "contains wheat flour, milk", "p soup", "Ana Ruiz")
    expect(response.body).to match(/covered_by">[^<]*milk/)
  end

  it "re-renders the form with errors" do
    post custom_items_path, params: { custom_item: { name: "milk" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Please fix")
  end

  it "rejects a parent outside the list" do
    theirs = item_for(stranger, name: "their soup")
    post custom_items_path, params: { custom_item: { name: "my soup", parent_id: theirs.id } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Kind of must be chosen from the list")
  end

  it "lists only her items, and never seeded nodes" do
    item_for(user, name: "mrs p's soup")
    item_for(stranger, name: "their soup")
    get custom_items_path
    expect(response.body).to include("mrs p&#39;s soup")
    expect(response.body).not_to include("their soup")
    expect(response.body).not_to include(">milk<")
  end

  it "never opens another nurse's item or a seeded node" do
    theirs = item_for(stranger, name: "their soup")
    [ theirs, node("milk") ].each do |other|
      get custom_item_path(other)
      expect(response).to have_http_status(:not_found)
      patch custom_item_path(other), params: { custom_item: { name: "hacked" } }
      expect(response).to have_http_status(:not_found)
      delete custom_item_path(other)
      expect(response).to have_http_status(:not_found)
      patch marks_custom_item_path(other), params: { marks: { ana.id => "cannot" } }
      expect(response).to have_http_status(:not_found)
    end
    expect(theirs.reload.name).to eq("their soup")
    expect(node("milk")).to be_present
    expect(ana.restrictions).to be_empty
  end

  it "edits an item" do
    item = item_for(user, name: "mrs p's soup")
    get edit_custom_item_path(item)
    expect(response.body).to include("Save custom item")
    patch custom_item_path(item), params: { custom_item: { name: "Mrs P's broth", ingredients_text: "milk" } }
    expect(response).to redirect_to(custom_item_path(item))
    expect(item.reload).to have_attributes(name: "mrs p's broth", ingredients_text: "milk")
    expect(item.groups.pluck(:name)).to include("milk")
  end

  it "marks patients can or cannot, as normal restrictions" do
    item = item_for(user, name: "mrs p's soup")
    other = create(:patient)
    expect do
      patch marks_custom_item_path(item), params: { marks: { ana.id => "cannot", other.id => "cannot" } }
    end.to change { ana.reload.profile_version }
    expect(response).to redirect_to(custom_item_path(item))
    expect(ana.restrictions.sole).to have_attributes(kind: "cannot", match_type: "manual", taxonomy_node_id: item.id)
    expect(other.restrictions).to be_empty

    get custom_item_path(item)
    expect(Capybara.string(response.body).find("##{ActionView::RecordIdentifier.dom_id(ana, :mark_cannot)}")).to be_checked
  end

  it "deletes an item and re-resolves restrictions that used it" do
    item = item_for(user, name: "mrs p's soup")
    restriction = ana.restrictions.create!(kind: :cannot, term: "mrs p's soup", manual_node_id: item.id)
    expect { delete custom_item_path(item) }.to change { ana.reload.profile_version }
    expect(response).to redirect_to(custom_items_path)
    expect(restriction.reload).to have_attributes(match_type: "unresolved", taxonomy_node_id: nil)
  end

  it "re-checks an ingredient with the new tier once added" do
    ana.restrictions.create!(kind: :allergy, term: "milk")
    post check_group_path, params: { patient_ids: [ ana.id ], ingredients: "mrs p's soup" }
    expect(response.body).to include("Add as custom item", new_custom_item_path(name: "mrs p's soup").gsub("&", "&amp;"))

    post custom_items_path, params: { custom_item: { name: "mrs p's soup", ingredients_text: "milk" } }
    post check_group_path, params: { patient_ids: [ ana.id ], ingredients: "mrs p's soup" }
    expect(response.body).to include("mrs p&#39;s soup is in the milk group (allergy)")
    expect(response.body).not_to include("Add as custom item")
  end

  describe "foods search" do
    it "offers to add the query as a custom item" do
      create(:food)
      get foods_path(q: "mrs p soup")
      link = Capybara.string(response.body).find_link("Add it as a custom item")
      expect(link[:href]).to eq(new_custom_item_path(name: "mrs p soup"))
      expect(link["data-turbo-frame"]).to eq("_top")
    end

    it "shows no link without a query" do
      get foods_path
      expect(response.body).not_to include("Add it as a custom item")
    end
  end
end
