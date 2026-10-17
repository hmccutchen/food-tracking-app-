require "rails_helper"

RSpec.describe Taxonomy::Seed do
  before { described_class.load! }

  def node(name) = TaxonomyNode.find_by!(name:)

  it "is idempotent" do
    counts = [ TaxonomyNode.count, TaxonomyAlias.count ]
    described_class.load!
    expect([ TaxonomyNode.count, TaxonomyAlias.count ]).to eq(counts)
  end

  it "restores a node's parent and kind when they drift" do
    node("almond").update!(parent: nil, kind: :category)
    described_class.load!
    expect(node("almond")).to have_attributes(parent: node("tree nut"), kind: "ingredient")
  end

  it "seeds the FDA top 9 allergens" do
    expect(TaxonomyNode.allergen.where(parent_id: nil).or(TaxonomyNode.where(name: "wheat")).pluck(:name))
      .to contain_exactly("milk", "egg", "fish", "shellfish", "tree nut", "peanut", "wheat", "soy", "sesame")
  end

  it "keeps peanut separate from tree nut" do
    expect(node("peanut").parent).to be_nil
    expect(node("tree nut").covers?(node("peanut"))).to be(false)
  end

  it "models gluten as a category covering wheat, barley, rye and malt" do
    gluten = node("gluten")
    expect(gluten).to be_category
    %w[wheat barley rye malt semolina].each { |name| expect(gluten.covers?(node(name))).to be(true), name }
    expect(node("wheat")).to be_allergen
  end

  it "makes lactose an intolerance under milk" do
    expect(node("lactose")).to have_attributes(kind: "intolerance", parent: node("milk"))
  end

  it "has an ambiguous-ingredient category" do
    expect(node("ambiguous ingredient").children.pluck(:name))
      .to contain_exactly("natural flavors", "spices", "stock", "seasoning")
  end
end
