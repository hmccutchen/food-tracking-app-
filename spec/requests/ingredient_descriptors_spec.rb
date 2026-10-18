require "rails_helper"

RSpec.describe "Descriptor words page" do
  before(:context) { Taxonomy::Seed.load! }
  after(:context) do
    TaxonomyNode.delete_all
    IngredientDescriptor.delete_all
  end

  let(:user) { create(:user) }
  let(:diced) { IngredientDescriptor.find_by!(word: "diced") }

  before { sign_in(user) }

  it "requires sign-in" do
    delete session_path
    get ingredient_descriptors_path
    expect(response).to redirect_to(new_session_path)
  end

  it "is linked from the preparation notes page" do
    get prep_methods_path
    expect(response.body).to include(%(href="#{ingredient_descriptors_path}"))
  end

  it "lists the words and the words that can never be added" do
    get ingredient_descriptors_path
    expect(response.body).to include("Descriptor words", "diced", "extra-virgin", "breaded")
  end

  it "adds a word" do
    post ingredient_descriptors_path, params: { ingredient_descriptor: { word: "Spiralized" } }
    expect(response).to redirect_to(ingredient_descriptors_path)
    expect(IngredientDescriptor.find_by(word: "spiralized")).to be_active
  end

  it "refuses a never word and shows why" do
    post ingredient_descriptors_path, params: { ingredient_descriptor: { word: "breaded" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("can&#39;t be a descriptor")
    expect(IngredientDescriptor.exists?(word: "breaded")).to be(false)
  end

  it "turns a word off" do
    get edit_ingredient_descriptor_path(diced)
    expect(response.body).to include("Use this word")
    patch ingredient_descriptor_path(diced), params: { ingredient_descriptor: { word: "diced", active: "0" } }
    expect(response).to redirect_to(ingredient_descriptors_path)
    expect(diced.reload).not_to be_active
  end

  it "re-renders the edit form on a bad word" do
    patch ingredient_descriptor_path(diced), params: { ingredient_descriptor: { word: "fried" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(diced.reload.word).to eq("diced")
  end
end
