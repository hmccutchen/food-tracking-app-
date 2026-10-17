require "rails_helper"

# Prep notes and the cross-contact line are advisory: they never change a tier.
RSpec.describe "Prep notes are advisory only" do
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { clear_prep_method_seed! }

  it "yields identical tiers and flags with and without prep notes present" do
    user = create(:user)
    ana = user.patients.create!(display_name: "Ana Ruiz")
    ben = user.patients.create!(display_name: "Ben Okafor")
    ana.restrictions.create!(kind: :allergy, term: "shellfish")
    ben.restrictions.create!(kind: :condition, term: "low sodium")
    ingredients = [ "fried shrimp", "chicken stock", "tempura batter", "rice" ]
    snapshot = lambda do |result|
      [ result.tier, result.patient_results.map { |patient_result| [ patient_result.tier, patient_result.flags ] } ]
    end

    expect(PrepMethod.count).to eq(0)
    without = Evaluation::Engine.new([ ana, ben ]).evaluate(ingredients)

    PrepMethodSeedData.load!
    notes = PrepNotes.for(patients: [ ana, ben ], dish: "Fried shrimp with stock", ingredients:)
    expect(notes.map(&:method_name)).to include("frying", "stock or broth")
    expect(PrepNotes.cross_contact_line([ ana, ben ])).to be_present
    with = Evaluation::Engine.new([ ana, ben ]).evaluate(ingredients)

    expect(snapshot.call(with)).to eq(snapshot.call(without))
  end

  it "is never referenced by the evaluation engine" do
    files = Rails.root.glob("app/models/evaluation/**/*.rb")
    expect(files).not_to be_empty
    offenders = files.select { |path| File.read(path).match?(/PrepNotes|PrepMethod|prep_method|cross_contact/) }
    expect(offenders).to be_empty
  end

  it "takes no evaluation result" do
    expect(PrepNotes.method(:for).parameters).to eq([ %i[keyreq patients], %i[keyreq dish], %i[keyreq ingredients],
      %i[key prep_notes] ])
  end
end
