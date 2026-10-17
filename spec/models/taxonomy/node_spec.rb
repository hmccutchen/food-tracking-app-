require "rails_helper"

RSpec.describe TaxonomyNode do
  subject(:node) { build(:taxonomy_node) }

  it { is_expected.to validate_presence_of(:name) }
  it "validates name uniqueness" do
    create(:taxonomy_node)
    expect(node).to validate_uniqueness_of(:name).ignoring_case_sensitivity
  end
  it { is_expected.to belong_to(:parent).optional }
  it { is_expected.to have_many(:children) }
  it { is_expected.to have_many(:aliases) }

  it "normalizes the name and derives a slug on save" do
    node = create(:taxonomy_node, name: "  Brazil   NUT! ")
    expect(node.name).to eq("brazil nut")
    expect(node.slug).to eq("brazil-nut")
  end

  it "rejects a duplicate name that differs only in case and spacing" do
    create(:taxonomy_node, name: "almond")
    duplicate = build(:taxonomy_node, name: " ALMOND ")
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:name]).to include("has already been taken")
  end

  it "rejects an unknown kind" do
    expect(build(:taxonomy_node, kind: "condiment")).not_to be_valid
  end

  it "stores kind as a string" do
    node = create(:taxonomy_node, kind: :allergen)
    expect(node.kind_before_type_cast).to eq("allergen")
    expect(node).to be_allergen
  end

  describe "tree" do
    let!(:root) { create(:taxonomy_node, name: "fish", kind: :allergen) }
    let!(:middle) { create(:taxonomy_node, name: "anchovy", parent: root) }
    let!(:leaf) { create(:taxonomy_node, name: "worcestershire sauce", parent: middle) }
    let!(:sibling) { create(:taxonomy_node, name: "cod", parent: root) }
    let!(:stranger) { create(:taxonomy_node, name: "peanut", kind: :allergen) }

    it "lists descendants across levels" do
      expect(root.descendants).to contain_exactly(middle, leaf, sibling)
      expect(middle.descendants).to contain_exactly(leaf)
      expect(leaf.descendants).to be_empty
    end

    it "lists ancestors nearest first" do
      expect(leaf.ancestors.to_a).to eq([ middle, root ])
      expect(root.ancestors).to be_empty
    end

    it "lists self_and_ancestors nearest first" do
      expect(leaf.self_and_ancestors.to_a).to eq([ leaf, middle, root ])
    end

    it "covers itself and its descendants only" do
      expect(root.covers?(root)).to be(true)
      expect(root.covers?(leaf)).to be(true)
      expect(middle.covers?(leaf)).to be(true)
      expect(leaf.covers?(root)).to be(false)
      expect(middle.covers?(sibling)).to be(false)
      expect(root.covers?(stranger)).to be(false)
      expect(root.covers?(nil)).to be(false)
    end

    it "refuses to make a node its own ancestor" do
      root.parent = leaf
      expect(root).not_to be_valid
      expect(root.errors[:parent]).to be_present

      leaf.parent = leaf
      expect(leaf).not_to be_valid
    end

    it "orphans children when a node is destroyed" do
      middle.destroy
      expect(leaf.reload.parent).to be_nil
    end
  end

  describe TaxonomyAlias do
    subject { build(:taxonomy_alias) }

    it { is_expected.to belong_to(:taxonomy_node) }
    it { is_expected.to validate_presence_of(:term) }
    it { is_expected.to validate_uniqueness_of(:term).ignoring_case_sensitivity }

    it "normalizes the term on save" do
      expect(create(:taxonomy_alias, term: " Almond   FLOUR ").term).to eq("almond flour")
    end

    it "is deleted with its node" do
      record = create(:taxonomy_alias)
      record.taxonomy_node.destroy
      expect(described_class.exists?(record.id)).to be(false)
    end

    it "cascades at the database level too" do
      record = create(:taxonomy_alias)
      TaxonomyNode.where(id: record.taxonomy_node_id).delete_all
      expect(described_class.exists?(record.id)).to be(false)
    end
  end
end
