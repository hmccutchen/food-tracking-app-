require "rails_helper"

RSpec.describe Evaluation::Engine do
  # The seed is read-only here (examples that delete a node roll back), so load it once.
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  let(:conflict) { Evaluation::Tier::CONFLICT }
  let(:possible) { Evaluation::Tier::POSSIBLE_CONFLICT }
  let(:unknown) { Evaluation::Tier::UNKNOWN }
  let(:none) { Evaluation::Tier::NONE }

  # patient_with(allergy: "tree nut", can: [ "almond" ])
  def patient_with(**restrictions)
    patient = create(:patient)
    restrictions.each do |kind, terms|
      Array(terms).each { |term| create(:restriction, patient:, kind:, term:) }
    end
    patient.reload
  end

  def evaluate(patients, ingredients)
    described_class.new(Array(patients)).evaluate(ingredients)
  end

  def result_for(patient, ingredients)
    evaluate(patient, ingredients).patient_results.sole
  end

  def summary(flags) = flags.map { |flag| [ flag.tier.to_sym, flag.source, flag.reason ] }

  describe "per-ingredient rules" do
    it "allergy covering the ingredient is a conflict" do
      result = result_for(patient_with(allergy: "tree nut"), [ "almond flour" ])
      expect(summary(result.flags)).to eq([ [ :conflict, :allergy, "almond flour is a tree nut (allergy)" ] ])
      expect(result.flags.sole.ingredient).to eq("almond flour")
      expect(result.tier).to eq(conflict)
    end

    it "cannot covering the same ingredient is a conflict" do
      result = result_for(patient_with(cannot: "shrimp"), [ "Shrimp" ])
      expect(summary(result.flags)).to eq([ [ :conflict, :cannot, "you marked Shrimp as cannot" ] ])
    end

    it "cannot covering a descendant names the restriction" do
      result = result_for(patient_with(cannot: "shellfish"), [ "prawn" ])
      expect(summary(result.flags)).to eq([ [ :conflict, :cannot, "prawn is under shellfish — you marked 'shellfish' as cannot" ] ])
    end

    it "intolerance covering the ingredient is a conflict" do
      result = result_for(patient_with(intolerance: "lactose intolerance"), [ "milk sugar" ])
      expect(summary(result.flags)).to eq([ [ :conflict, :intolerance, "milk sugar is lactose (lactose intolerance)" ] ])
    end

    it "condition covering the ingredient is a possible conflict" do
      result = result_for(patient_with(condition: "low sodium"), [ "soy sauce" ])
      expect(summary(result.flags)).to eq([ [ :possible_conflict, :condition, "soy sauce is high in sodium (low sodium)" ] ])
    end

    it "condition covering through the tree is a possible conflict" do
      result = result_for(patient_with(condition: "diabetic"), [ "honey" ])
      expect(summary(result.flags)).to eq([ [ :possible_conflict, :condition, "honey is high in added sugar (diabetic)" ] ])
    end

    it "a fuzzy-matched ingredient is only a possible conflict, even for an allergy" do
      result = result_for(patient_with(allergy: "tree nut"), [ "almnd flour" ])
      expect(result.flags.sole).to have_attributes(tier: possible, source: :fuzzy)
      expect(result.flags.sole.reason).to eq(
        "almnd flour: fuzzy match to almond, which is under tree nut — check the label (allergy)"
      )
      expect(result.flags.sole.reason).to include("fuzzy match")
    end

    it "a fuzzy-matched ingredient against a cannot is a possible conflict" do
      result = result_for(patient_with(cannot: "soy sauce"), [ "soy sauc" ])
      # No unknown: the scan finds "soy" inside the misspelling.
      expect(summary(result.flags)).to eq([ [ :possible_conflict, :fuzzy,
        "soy sauc: fuzzy match to soy sauce — check the label (cannot)" ] ])
    end

    it "an ambiguous ingredient is a possible conflict for a patient with an allergy" do
      result = result_for(patient_with(allergy: "peanut"), [ "natural flavors" ])
      expect(summary(result.flags)).to eq([ [ :possible_conflict, :ambiguous, "'natural flavors' listed — may hide allergens" ] ])
    end

    %i[intolerance cannot].each do |kind|
      it "an ambiguous ingredient is a possible conflict for a patient with a #{kind}" do
        result = result_for(patient_with(kind => "lactose"), [ "Spices" ])
        expect(summary(result.flags)).to eq([ [ :possible_conflict, :ambiguous, "'Spices' listed — may hide allergens" ] ])
      end
    end

    it "an ambiguous alias or fuzzy spelling still counts as ambiguous" do
      result = result_for(patient_with(allergy: "peanut"), [ "broth", "natural flavour" ])
      # The misspelling is also unknown: a loose match with nothing known inside it.
      expect(result.flags.map(&:source)).to eq(%i[ambiguous ambiguous unresolved])
    end

    it "an ambiguous ingredient raises no flag for a patient with only conditions or cans" do
      result = result_for(patient_with(condition: "diabetic", can: "honey"), [ "natural flavors" ])
      expect(result.flags).to be_empty
      expect(result.tier).to eq(none)
    end

    it "an unresolved ingredient is unknown, never a pass" do
      result = result_for(patient_with(allergy: "peanut"), [ "xyzzy" ])
      expect(summary(result.flags)).to eq([ [ :unknown, :unresolved, "'xyzzy' not recognized" ] ])
    end

    it "an unresolved ingredient is unknown even for a patient with no restrictions" do
      expect(result_for(patient_with, [ "xyzzy" ]).tier).to eq(unknown)
    end

    [ nil, [], [ "", "  " ] ].each do |ingredients|
      it "no ingredient list (#{ingredients.inspect}) is unknown for every patient" do
        patients = [ patient_with(allergy: "peanut"), patient_with ]
        result = evaluate(patients, ingredients)

        expect(result.patient_results.size).to eq(2)
        result.patient_results.each do |patient_result|
          expect(summary(patient_result.flags)).to eq([ [ :unknown, :missing_list, "no ingredient list found" ] ])
        end
        expect(result.tier).to eq(unknown)
      end
    end

    it "a resolved ingredient no restriction covers raises no flag" do
      result = result_for(patient_with(allergy: "peanut", condition: "low sodium"), [ "almond", "banana" ])
      expect(result.flags).to be_empty
    end
  end

  describe "hierarchy and group membership" do
    it "tree nut allergy covers almond flour" do
      expect(result_for(patient_with(allergy: "tree nuts"), [ "almond flour" ]).tier).to eq(conflict)
    end

    it "low sodium covers soy sauce through membership" do
      expect(result_for(patient_with(condition: "low sodium"), [ "soy sauce" ]).tier).to eq(possible)
    end

    it "soy allergy covers soy sauce through the tree" do
      result = result_for(patient_with(allergy: "soy"), [ "soy sauce" ])
      expect(summary(result.flags)).to eq([ [ :conflict, :allergy, "soy sauce is a soy (allergy)" ] ])
    end

    it "peanut allergy does not cover almond" do
      expect(result_for(patient_with(allergy: "peanut"), [ "almond" ]).flags).to be_empty
    end

    it "a narrower restriction does not cover its parent" do
      expect(result_for(patient_with(allergy: "almond"), [ "tree nut" ]).flags).to be_empty
    end

    it "membership covers descendants of the member (sodium covers bacon under cured meat)" do
      expect(result_for(patient_with(condition: "low sodium"), [ "pancetta" ]).tier).to eq(possible)
    end

    it "agrees with TaxonomyNode#covers? for every top-level and mid-level node against every seed node" do
      nodes = TaxonomyNode.all.to_a
      restriction_nodes = nodes.select { |node| node.parent_id.nil? } +
        nodes.select { |node| node.name.in?([ "wheat", "almond", "cured meat", "anchovy", "cheese", "lactose" ]) }
      engine = described_class::Coverage.new(nodes)
      mismatches = restriction_nodes.product(nodes).reject do |restriction_node, ingredient_node|
        engine.relation(restriction_node, ingredient_node).present? == restriction_node.covers?(ingredient_node)
      end
      expect(mismatches.map { |pair| pair.map(&:name) }).to be_empty
    end
  end

  describe "several flags for one ingredient" do
    it "keeps an allergy and a condition flag for the same ingredient" do
      result = result_for(patient_with(allergy: "soy", condition: "low sodium"), [ "soy sauce" ])
      expect(summary(result.flags)).to eq([
        [ :conflict, :allergy, "soy sauce is a soy (allergy)" ],
        [ :possible_conflict, :condition, "soy sauce is high in sodium (low sodium)" ]
      ])
      expect(result.tier).to eq(conflict)
    end

    it "dedupes exact duplicates from repeated ingredients and overlapping restrictions" do
      result = result_for(patient_with(allergy: [ "tree nut", "nuts" ]), [ "almond", "almond" ])
      expect(summary(result.flags)).to eq([ [ :conflict, :allergy, "almond is a tree nut (allergy)" ] ])
    end

    it "keeps a separate flag per ingredient" do
      result = result_for(patient_with(allergy: "tree nut"), [ "almond", "walnut", "xyzzy" ])
      expect(result.flags.map(&:ingredient)).to eq(%w[almond walnut xyzzy])
    end
  end

  describe "restrictions without a taxonomy node (text fallback)" do
    it "the restriction term is unresolved in the seed" do
      restriction = create(:restriction, kind: :cannot, term: "grapefruit")
      expect(restriction).to have_attributes(taxonomy_node: nil, match_type: "unresolved")
    end

    it "cannot 'grapefruit' matches 'grapefruit juice' as a whole word" do
      result = result_for(patient_with(cannot: "grapefruit"), [ "grapefruit juice" ])
      expect(summary(result.flags)).to eq([
        [ :conflict, :cannot, "grapefruit juice: text match to 'grapefruit' (cannot)" ],
        [ :unknown, :unresolved, "'grapefruit juice' not recognized" ]
      ])
    end

    it "cannot 'grapefruit' does not match 'grape'" do
      result = result_for(patient_with(cannot: "grapefruit"), [ "grape", "grape juice" ])
      expect(result.flags.map(&:source)).to all(eq(:unresolved))
    end

    it "does not match inside a longer word" do
      result = result_for(patient_with(allergy: "kiwi"), [ "kiwifruit", "dried kiwi slices" ])
      expect(result.flags.select { |flag| flag.source == :allergy }.map(&:ingredient)).to eq([ "dried kiwi slices" ])
    end

    it "a plural restriction term matches its singular" do
      result = result_for(patient_with(allergy: "kiwis"), [ "kiwi" ])
      expect(result.flags.map(&:source)).to include(:allergy)
    end

    it "a condition text match is a possible conflict" do
      result = result_for(patient_with(condition: "gout purines"), [ "high gout purines extract" ])
      expect(result.flags.first).to have_attributes(tier: possible, source: :condition,
        reason: "high gout purines extract: text match to 'gout purines' (gout purines)")
    end

    it "applies to a resolved ingredient too" do
      result = result_for(patient_with(allergy: "grapefruit"), [ "orange and grapefruit" ])
      expect(result.flags.map(&:source)).to include(:allergy)
    end

    it "falls back to text when the restriction's node was deleted (match_type is left as it was)" do
      patient = patient_with(allergy: "sesame")
      restriction = patient.restrictions.sole
      expect(restriction.match_type).to eq("exact")

      TaxonomyNode.find_by!(name: "sesame").destroy!
      expect(restriction.reload.taxonomy_node).to be_nil
      expect(restriction.match_type).to eq("exact")

      result = result_for(patient, [ "sesame oil", "tahini" ])
      expect(summary(result.flags)).to eq([ [ :conflict, :allergy, "sesame oil: text match to 'sesame' (allergy)" ] ])
    end
  end

  describe "restrictions that were fuzzy-matched at entry" do
    it "still produce their kind's normal tier and name the nurse's entry" do
      patient = patient_with(allergy: "peanutt")
      expect(patient.restrictions.sole.match_type).to eq("fuzzy")

      result = result_for(patient, [ "peanut butter" ])
      expect(summary(result.flags)).to eq([ [ :conflict, :allergy,
        "peanut butter is peanut (allergy) — you entered 'peanutt', matched to peanut" ] ])
    end
  end

  describe "phrases that contain a known ingredient" do
    {
      "toasted sliced almonds" => "tree nut", "roasted almonds" => "tree nut", "almond-crusted tilapia" => "tree nut",
      "egg noodles" => "egg", "grated parmesan cheese" => "milk", "low-sodium soy sauce" => "soy",
      "shrimp stock" => "shellfish"
    }.each do |phrase, allergy|
      it "#{phrase.inspect} is a conflict for a #{allergy} allergy" do
        result = result_for(patient_with(allergy:), [ phrase ])
        expect(result.tier).to eq(conflict)
        expect(result.active_flags.map(&:source)).to include(:allergy)
      end
    end

    it "names the contained phrase and the restriction in the reason" do
      result = result_for(patient_with(allergy: "soy"), [ "low-sodium soy sauce" ])
      expect(result.active_flags.find { |flag| flag.source == :allergy }.reason)
        .to eq("'soy sauce' appears in 'low-sodium soy sauce' (allergy)")
    end

    it "'low-sodium soy sauce' is a conflict for soy and a possible conflict for low sodium" do
      soy = patient_with(allergy: "soy")
      sodium = patient_with(condition: "low sodium")
      result = evaluate([ soy, sodium ], [ "low-sodium soy sauce" ])

      expect(result.for_patient(soy.id).tier).to eq(conflict)
      expect(result.for_patient(sodium.id).tier).to eq(possible)
      expect(result.for_patient(sodium.id).flags.map(&:reason))
        .to include("'soy sauce' appears in 'low-sodium soy sauce' (low sodium)")
    end

    it "keeps the whole-phrase unknown flag" do
      result = result_for(patient_with(allergy: "tree nut"), [ "roasted almonds" ])
      expect(summary(result.flags)).to eq([
        [ :conflict, :allergy, "'almonds' appears in 'roasted almonds' (allergy)" ],
        [ :unknown, :unresolved, "'roasted almonds' not recognized" ]
      ])
    end

    it "keeps the whole-phrase fuzzy flag" do
      result = result_for(patient_with(allergy: "shellfish"), [ "shrimp stock" ])
      expect(result.flags.map(&:source)).to contain_exactly(:fuzzy, :allergy, :ambiguous)
      expect(result.tier).to eq(conflict)
    end

    it "an alias wins over the scan: 'almond milk' is not milk" do
      expect(result_for(patient_with(allergy: "milk"), [ "almond milk" ]).flags).to be_empty
      expect(result_for(patient_with(allergy: "tree nut"), [ "almond milk" ]).tier).to eq(conflict)
    end

    it "takes the longest match: 'peanut butter cookies' is peanut, not butter" do
      expect(result_for(patient_with(allergy: "peanut"), [ "peanut butter cookies" ]).tier).to eq(conflict)
      expect(result_for(patient_with(allergy: "milk"), [ "peanut butter cookies" ]).flags).to be_empty
    end

    it "accepts the documented false positive: 'butter lettuce' is a milk conflict" do
      result = result_for(patient_with(allergy: "milk"), [ "butter lettuce" ])
      expect(result.tier).to eq(conflict)
      expect(result.active_flags.map(&:reason)).to include("'butter' appears in 'butter lettuce' (allergy)")
    end

    it "runs the ambiguous check on contained nodes" do
      result = result_for(patient_with(allergy: "peanut"), [ "chicken stock" ])
      expect(result.tier).to eq(possible)
      expect(result.flags.map(&:reason)).to include("'stock' appears in 'chicken stock' — may hide allergens")
    end

    it "a restriction fuzzy-matched at entry still names the entry" do
      result = result_for(patient_with(allergy: "peanutt"), [ "crushed peanuts" ])
      expect(result.active_flags.map(&:reason))
        .to include("'peanuts' appears in 'crushed peanuts' (allergy) — you entered 'peanutt', matched to peanut")
    end

    describe "with can and cannot" do
      it "a can never clears a contained allergy" do
        result = result_for(patient_with(allergy: "tree nut", can: "almond"), [ "roasted almonds" ])
        expect(result.tier).to eq(conflict)
        expect(result.overridden_flags.map(&:reason)).to eq([ "you marked 'almond' as can, but the allergy still applies" ])
      end

      it "a can clears a contained intolerance flag and keeps it visible" do
        result = result_for(patient_with(intolerance: "lactose", can: "lactose"), [ "lactose-reduced xyzzy" ])
        expect(result.overridden_flags.map(&:source)).to eq([ :intolerance ])
        expect(result.active_flags.map(&:source)).to eq([ :unresolved ])
      end

      it "a cannot wins over a can on a contained node" do
        result = result_for(patient_with(cannot: "egg", can: "egg"), [ "egg noodles" ])
        expect(result.tier).to eq(conflict)
        expect(result.overridden_flags.map(&:reason)).to eq([ "you marked 'egg' as can, but a cannot always wins" ])
      end
    end

    describe "realistic AI ingredient phrases" do
      allergies = [ "milk", "egg", "fish", "shellfish", "tree nut", "peanut", "wheat", "soy", "sesame" ].freeze

      # phrase => { allergy => worst tier }; allergies not listed expect the default.
      {
        "extra-virgin olive oil" => { default: :unknown },
        "chicken stock" => { default: :possible_conflict },
        "whole wheat tortillas" => { "wheat" => :conflict, default: :none },
        "shredded cheddar cheese" => { "milk" => :conflict, default: :none },
        "toasted sesame oil" => { "sesame" => :conflict, default: :none },
        "fish sauce" => { "fish" => :conflict, default: :none },
        "egg wash" => { "egg" => :conflict, default: :none },
        "unsalted butter" => { "milk" => :conflict, default: :none },
        "large eggs" => { "egg" => :conflict, default: :unknown },
        "heavy whipping cream" => { "milk" => :conflict, default: :none },
        "crushed peanuts" => { "peanut" => :conflict, default: :none },
        "chopped walnuts" => { "tree nut" => :conflict, default: :unknown },
        "canned tuna in water" => { "fish" => :conflict, default: :none },
        "cooked shrimp, peeled" => { "shellfish" => :conflict, default: :unknown },
        "soy milk" => { "soy" => :conflict, default: :none },
        "sesame seeds" => { "sesame" => :conflict, default: :none },
        "panko bread crumbs" => { "wheat" => :conflict, default: :none },
        "unsweetened almond milk" => { "tree nut" => :conflict, default: :none },
        "greek yogurt" => { "milk" => :conflict, default: :none },
        "low-sodium soy sauce" => { "soy" => :conflict, default: :none },
        "grated parmesan cheese" => { "milk" => :conflict, default: :unknown },
        "lemon juice" => { default: :unknown }
      }.each do |phrase, expected|
        it "#{phrase.inspect} gets the expected worst tier for each allergy" do
          patients = allergies.index_with { |allergy| patient_with(allergy:) }
          result = evaluate(patients.values, [ phrase ])

          actual = patients.transform_values { |patient| result.for_patient(patient.id).tier.to_sym }
          wanted = allergies.index_with { |allergy| expected.fetch(allergy, expected[:default]) }
          expect(actual).to eq(wanted)
          expect(result.tier).to eq(Evaluation::Tier.worst(wanted.values))
        end
      end
    end
  end

  describe "lactose intolerance" do
    %w[milk whey cheese butter cream].each do |ingredient|
      it "is a conflict for #{ingredient}, which contains lactose" do
        result = result_for(patient_with(intolerance: "lactose intolerance"), [ ingredient ])
        expect(result.tier).to eq(conflict)
      end
    end

    it "is a conflict for a phrase containing milk" do
      result = result_for(patient_with(intolerance: "lactose"), [ "shredded cheddar cheese" ])
      expect(result.tier).to eq(conflict)
    end

    it "does not reach a non-dairy item" do
      result = result_for(patient_with(intolerance: "lactose"), [ "olive oil" ])
      expect(result.active_flags.map(&:source)).not_to include(:intolerance)
    end
  end

  describe "overrides and precedence" do
    it "a can on one part of a phrase never clears a text match on another part" do
      result = result_for(patient_with(intolerance: "sorbitol", can: "banana"), [ "banana with sorbitol" ])
      expect(result.tier).to eq(conflict)
      expect(result.active_flags.map(&:source)).to include(:intolerance)
    end

    it "a can for the same unrecognized term clears its text match" do
      result = result_for(patient_with(intolerance: "sorbitol", can: "sorbitol"), [ "banana with sorbitol" ])
      expect(result.overridden_flags.map(&:source)).to include(:intolerance)
    end

    it "cannot beats can on the same node" do
      result = result_for(patient_with(can: "shrimp", cannot: "shrimp"), [ "shrimp" ])
      expect(result.tier).to eq(conflict)
      expect(result.active_flags.map(&:source)).to eq([ :cannot ])
      expect(result.overridden_flags.sole).to have_attributes(override_reason: "you marked this OK",
        reason: "you marked 'shrimp' as can, but a cannot always wins")
    end

    it "cannot beats can and keeps intolerance flags active too" do
      result = result_for(patient_with(intolerance: "lactose", can: "lactose", cannot: "milk"), [ "lactose" ])
      expect(result.active_flags.map(&:source)).to contain_exactly(:intolerance, :cannot)
      expect(result.tier).to eq(conflict)
    end

    it "can never silences an allergy, and shows 'you marked this OK' alongside it" do
      result = result_for(patient_with(allergy: "peanut", can: "peanut"), [ "peanut" ])
      expect(result.tier).to eq(conflict)
      expect(result.active_flags.sole).to have_attributes(source: :allergy, tier: conflict)
      expect(result.overridden_flags.sole).to have_attributes(override_reason: "you marked this OK",
        reason: "you marked 'peanut' as can, but the allergy still applies")
    end

    it "can on a narrower node does not clear an allergy on its ancestor" do
      result = result_for(patient_with(allergy: "tree nut", can: "almond"), [ "almond flour" ])
      expect(result.tier).to eq(conflict)
      expect(result.active_flags.sole.reason).to eq("almond flour is a tree nut (allergy)")
      expect(result.overridden_flags.map(&:override_reason)).to eq([ "you marked this OK" ])
    end

    it "can on a broader node does not clear an allergy on a descendant" do
      result = result_for(patient_with(allergy: "almond", can: "tree nut"), [ "almond flour" ])
      expect(result.tier).to eq(conflict)
    end

    it "can never clears a fuzzy flag raised by an allergy" do
      result = result_for(patient_with(allergy: "peanut", can: "peanut"), [ "peanutt" ])
      expect(result.tier).to eq(possible)
      expect(result.active_flags.map(&:source)).to eq(%i[fuzzy unresolved])
      expect(result.overridden_flags.sole.override_reason).to eq("you marked this OK")
    end

    it "can on lactose clears a lactose intolerance flag but keeps it visible" do
      result = result_for(patient_with(intolerance: "lactose", can: "lactose"), [ "lactose" ])
      expect(result.tier).to eq(none)
      expect(result).to be_no_flags
      expect(result.overridden_flags.sole).to have_attributes(source: :intolerance, tier: conflict, overridden: true,
        override_reason: "you marked this OK", reason: "lactose is listed (lactose intolerance)")
    end

    it "can clears a condition flag" do
      result = result_for(patient_with(condition: "low sodium", can: "soy sauce"), [ "soy sauce", "bacon" ])
      expect(result.overridden_flags.map(&:ingredient)).to eq([ "soy sauce" ])
      expect(result.active_flags.map(&:ingredient)).to eq([ "bacon" ])
      expect(result.tier).to eq(possible)
    end

    it "can clears an ambiguous flag" do
      result = result_for(patient_with(allergy: "peanut", can: "natural flavors"), [ "natural flavors" ])
      expect(result.tier).to eq(none)
      expect(result.overridden_flags.sole.source).to eq(:ambiguous)
    end

    it "can clears a fuzzy flag raised by an intolerance" do
      result = result_for(patient_with(intolerance: "lactose", can: "lactose"), [ "lactos" ])
      # The fuzzy flag is cleared; the loose match itself stays unknown, which a can never clears.
      expect(result.tier).to eq(unknown)
      expect(result.overridden_flags.sole).to have_attributes(source: :fuzzy, override_reason: "you marked this OK")
    end

    it "can never clears unknown" do
      result = result_for(patient_with(can: "xyzzy"), [ "xyzzy" ])
      expect(summary(result.active_flags)).to eq([ [ :unknown, :unresolved, "'xyzzy' not recognized" ] ])
      expect(result.tier).to eq(unknown)
    end

    it "a can that matches by text clears a condition flag but not the unknown" do
      result = result_for(patient_with(condition: "gout purines", can: "gout purines"), [ "gout purines mix" ])
      expect(result.overridden_flags.map(&:source)).to eq([ :condition ])
      expect(result.tier).to eq(unknown)
    end

    it "a can on an unrelated node changes nothing" do
      result = result_for(patient_with(intolerance: "lactose", can: "banana"), [ "lactose" ])
      expect(result.tier).to eq(conflict)
      expect(result.overridden_flags).to be_empty
    end
  end

  describe "rolling up across patients" do
    it "is a conflict when one patient has a conflict, one a possible conflict and one nothing" do
      allergic = patient_with(allergy: "soy")
      sodium = patient_with(condition: "low sodium")
      clear = patient_with(allergy: "shellfish")

      result = evaluate([ allergic, sodium, clear ], [ "soy sauce" ])
      expect(result.patient_results.map(&:patient_id)).to eq([ allergic.id, sodium.id, clear.id ])
      expect(result.patient_results.map(&:tier)).to eq([ conflict, possible, none ])
      expect(result.tier).to eq(conflict)
      expect(result.conflicts.map(&:reason)).to eq([ "soy sauce is a soy (allergy)" ])
      expect(result.blocking_ingredients).to eq([ "soy sauce" ])
    end

    it "is never softer than any patient for random restriction mixes" do
      # Each profile produces a known tier against "soy sauce".
      profiles = {
        conflict => { allergy: "soy" }, possible => { condition: "low sodium" },
        none => { allergy: "shellfish" }, unknown => {}
      }
      random = Random.new(42)
      patients = profiles.transform_values { |restrictions| Array.new(2) { patient_with(**restrictions) } }

      30.times do
        chosen = Array.new(random.rand(1..4)) { profiles.keys.sample(random:) }
        selected = chosen.each_with_index.map { |tier, index| patients[tier][index % 2] }.uniq
        ingredients = chosen.include?(unknown) ? [ "soy sauce", "xyzzy" ] : [ "soy sauce" ]
        result = evaluate(selected, ingredients)

        expect(result.patient_results.map(&:tier)).to all(satisfy { |tier| result.tier >= tier })
        expect(result.tier).to eq(Evaluation::Tier.worst(result.patient_results.map(&:tier)))
      end
    end

    it "accepts patient ids and skips patients that no longer exist" do
      patient = patient_with(allergy: "peanut")
      result = described_class.new([ patient.id, 0 ]).evaluate([ "peanut" ])
      expect(result.patient_results.map(&:patient_id)).to eq([ patient.id ])
      expect(result.missing_patient_ids).to eq([ 0 ])
    end

    it "summarises a clean result without promising anything" do
      result = evaluate([ patient_with(allergy: "peanut"), patient_with(condition: "low sodium") ], [ "banana", "flour" ])
      expect(result.tier).to eq(none)
      expect(result.summary).to eq("No flags found — this isn't a guarantee")
    end
  end

  describe "profile versions and staleness" do
    let!(:patient) { patient_with(allergy: "peanut") }
    let!(:other) { patient_with(condition: "low sodium") }
    let(:result) { evaluate([ patient, other ], [ "peanut" ]) }

    it "stamps each patient's profile_version" do
      expect(result.profile_versions).to eq(patient.id => patient.profile_version, other.id => other.profile_version)
      expect(result.patient_results.map(&:profile_version)).to eq([ patient.profile_version, other.profile_version ])
      expect(result.evaluated_at).to be_within(1.minute).of(Time.current)
    end

    it "stays fresh when nothing changes" do
      expect(result).not_to be_stale
    end

    it "is stale once a restriction is added" do
      result
      create(:restriction, patient: other, kind: :allergy, term: "milk")
      expect(result).to be_stale
    end

    it "is stale once a patient's own fields change" do
      result
      patient.update!(notes: "new note")
      expect(result).to be_stale
    end

    it "is stale when a selected patient was already gone at evaluation time" do
      gone = patient_with
      gone_id = gone.id
      gone.destroy!

      result = evaluate([ patient, gone_id ], [ "peanut" ])
      expect(result.missing_patient_ids).to eq([ gone_id ])
      expect(result.profile_versions.keys).to eq([ patient.id ])
      expect(result).to be_stale
    end

    it "has no missing patients normally" do
      expect(result.missing_patient_ids).to eq([])
    end

    it "is stale once a patient is deleted" do
      result
      other.destroy!
      expect(result).to be_stale
    end

    it "offers a class-level check that a persisted stamp can reuse, with string keys" do
      stamp = result.profile_versions.to_h { |id, version| [ id.to_s, version ] }
      expect(Evaluation::GroupResult.stale_for?(stamp)).to be(false)
      expect(Evaluation::GroupResult.stale_for?(stamp.merge(patient.id.to_s => patient.profile_version - 1))).to be(true)
      expect(Evaluation::GroupResult.stale_for?({})).to be(false)
    end
  end

  describe "purity" do
    it "makes no network requests" do
      allow(Net::HTTP).to receive(:new).and_call_original
      allow(Net::HTTP).to receive(:start).and_call_original
      WebMock.reset!

      evaluate([ patient_with(allergy: "tree nut", condition: "low sodium") ], [ "almond flour", "almnd", "xyzzy" ])

      expect(Net::HTTP).not_to have_received(:new)
      expect(Net::HTTP).not_to have_received(:start)
      expect(WebMock::RequestRegistry.instance.requested_signatures.hash).to be_empty
    end

    it "has no HTTP or AI clients in its source" do
      source = Rails.root.glob("app/models/evaluation/**/*.rb").map(&:read).join("\n")
      expect(source).not_to match(/Net::HTTP|Faraday|HTTParty|RestClient|URI\.open|Anthropic|OpenAI|ruby_llm/i)
    end
  end

  describe "query count" do
    def count_queries
      count = 0
      callback = lambda do |*, payload|
        count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) || payload[:sql].match?(/\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/i)
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
      count
    end

    let(:ingredients) { [ "almond flour", "soy sauce", "milk sugar", "natural flavors", "shrimp", "honey", "bacon", "peanut" ] }
    let(:phrases) do
      [ "toasted sliced almonds with a pinch of sea salt and cracked black pepper", "low-sodium soy sauce",
        "grated parmesan cheese", "egg noodles", "shrimp stock", "almond flour" ]
    end

    def make_patients(count)
      Array.new(count) do
        patient_with(allergy: [ "tree nut", "peanut" ], intolerance: "lactose", condition: [ "low sodium", "diabetic" ],
          cannot: [ "shrimp", "grapefruit" ], can: "honey")
      end
    end

    it "uses a fixed number of queries, however many patients and restrictions" do
      one = make_patients(1)
      many = make_patients(6)

      single = count_queries { evaluate(one, ingredients) }
      several = count_queries { evaluate(many, ingredients) }

      expect(several).to eq(single)
      expect(several).to be <= 10
    end

    it "stays fixed with long phrases: the scan adds no queries beyond the resolver's fuzzy lookups" do
      one = make_patients(1)
      many = make_patients(6)
      single = count_queries { evaluate(one, phrases) }
      several = count_queries { evaluate(many, phrases) }
      loose = Taxonomy::Resolver.new.resolve_all(phrases).count { |result| !result.match_type.in?(%i[exact alias]) }

      expect(several).to eq(single)
      # 8 base queries (as above) plus the resolver's two fuzzy lookups per loose phrase.
      expect(several).to eq(8 + (2 * loose))
    end
  end

  describe "wording" do
    it "never uses the word 'safe' in the engine's code or strings" do
      offenders = Rails.root.glob("app/models/evaluation/**/*.rb").select { |path| path.read.match?(/\bsafe\b/i) }
      expect(offenders).to be_empty
    end
  end
end
