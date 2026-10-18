require "rails_helper"

RSpec.describe PrepNotes do
  before(:context) { load_prep_method_seed! }
  after(:context) { clear_prep_method_seed! }

  let(:user) { create(:user) }
  let(:ana) { create(:patient, user:, display_name: "Ana Ruiz") }
  let(:ben) { create(:patient, user:, display_name: "Ben Okafor") }

  def restrict(patient, kind, term) = patient.restrictions.create!(kind:, term:)
  def notes(patients, dish: nil, ingredients: [], prep_notes: [])
    described_class.for(patients:, dish:, ingredients:, prep_notes:)
  end
  def names(list) = list.map(&:method_name)

  describe "detection" do
    before { restrict(ana, :allergy, "shellfish") }

    it "finds a method in the dish name" do
      expect(names(notes([ ana ], dish: "Fried shrimp"))).to include("frying")
    end

    it "finds a method in a prep note" do
      expect(names(notes([ ana ], dish: "Shrimp", prep_notes: [ "Grill over high heat" ]))).to eq([ "grilling" ])
    end

    it "finds a method in an ingredient" do
      expect(names(notes([ ana ], ingredients: [ "tempura batter", "rice" ]))).to eq([ "frying" ])
    end

    it "matches whole words only: 'fry' never matches 'fryer'" do
      expect(notes([ ana ], dish: "Air fryer vegetables")).to be_empty
      expect(names(notes([ ana ], dish: "Pan-fried noodles"))).to eq([ "frying" ])
    end

    it "returns nothing when no method is mentioned" do
      expect(notes([ ana ], dish: "Steamed rice", ingredients: [ "rice", "water" ])).to be_empty
    end
  end

  describe "triggering" do
    it "needs a selected patient's restriction to cover one of the method's risk nodes" do
      restrict(ana, :allergy, "tree nuts")
      expect(notes([ ana ], dish: "Grilled salmon")).to be_empty
      expect(names(notes([ ana ], dish: "Apple pie"))).to eq([ "baking or pastry" ])
    end

    it "covers descendants: a gluten intolerance covers wheat" do
      restrict(ana, :intolerance, "gluten")
      expect(names(notes([ ana ], dish: "Breaded cutlet"))).to eq([ "breading" ])
    end

    it "uses group membership like the engine: low sodium triggers stock" do
      restrict(ben, :condition, "low sodium")
      note = notes([ ben ], dish: "Chicken soup").sole
      expect(note.method_name).to eq("stock or broth")
      expect(note.terms).to eq([ "low sodium" ])
    end

    it "is triggered by a narrower restriction under a risk node: a shrimp allergy and shared fryer oil" do
      restrict(ana, :allergy, "shrimp")
      expect(names(notes([ ana ], dish: "French fries", ingredients: [ "potato" ]))).to eq([ "frying" ])
    end

    it "is triggered by cannot restrictions" do
      restrict(ana, :cannot, "fish sauce")
      expect(names(notes([ ana ], dish: "Marinated pork"))).to eq([ "marinade" ])
    end

    it "is not triggered by a restriction the resolver could not map" do
      restrict(ana, :allergy, "zzqx blorp")
      expect(notes([ ana ], dish: "Fried shrimp")).to be_empty
    end

    it "is not triggered by a can" do
      restrict(ana, :can, "shellfish")
      expect(notes([ ana ], dish: "Fried shrimp")).to be_empty
    end

    it "ignores unselected patients" do
      restrict(ben, :allergy, "shellfish")
      expect(notes([ ana ], dish: "Fried shrimp")).to be_empty
    end

    it "ignores inactive methods" do
      restrict(ana, :allergy, "shellfish")
      PrepMethod.find_by!(name: "frying").update!(active: false)
      expect(notes([ ana ], dish: "Fried shrimp")).to be_empty
    end
  end

  describe "a note" do
    before do
      restrict(ana, :allergy, "shellfish")
      restrict(ben, :allergy, "Peanuts")
    end

    let(:note) { notes([ ana, ben ], dish: "Fried shrimp").sole }

    it "names the method, the risk, the relevant terms and the lower-risk line with its caveat" do
      expect(note.method_name).to eq("frying")
      expect(note.risk).to include("Fryer oil is often shared")
      expect(note.terms).to contain_exactly("shellfish", "peanuts")
      expect(note.lower_risk_line).to eq("Lower-risk method: bake or pan-sear in fresh oil — still check shared pans and utensils")
    end

    it "never carries patient names" do
      text = note.to_h.values.flatten.join(" ")
      expect(text).not_to include("Ana", "Ruiz", "Ben", "Okafor")
    end

    it "has a stable key that does not reveal terms and changes when the terms change" do
      again = notes([ ana, ben ], dish: "Deep-fried shrimp").sole
      expect(again.key).to eq(note.key)
      expect(note.key).to match(/\Aprep-\d+-\h{16}\z/)
      expect(notes([ ana ], dish: "Fried shrimp").sole.key).not_to eq(note.key)
    end
  end

  describe ".cross_contact_line" do
    it "is a reminder when any selected patient has an allergy, else nil" do
      restrict(ana, :intolerance, "lactose")
      expect(described_class.cross_contact_line([ ana ])).to be_nil
      restrict(ben, :allergy, "sesame")
      expect(described_class.cross_contact_line([ ana, ben ])).to eq("Check shared pans, oil, and cutting boards")
      expect(described_class.cross_contact_line([])).to be_nil
    end
  end
end
