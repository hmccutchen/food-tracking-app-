require "rails_helper"

RSpec.describe Taxonomy::Resolver do
  subject(:resolver) { described_class.new }

  # The seed is read-only here, so load it once for the group rather than per example.
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  def node(name) = TaxonomyNode.find_by!(name:)

  describe "#resolve" do
    [ "no nuts", "tree nuts", "Tree Nut", "tree nut", "nut-free", "nuts", "Nut Free", "without tree nuts",
     "free of nuts", "avoid nuts", "NO NUTS!" ].each do |text|
      it "resolves #{text.inspect} to tree nut" do
        expect(resolver.resolve(text).node).to eq(node("tree nut"))
      end
    end

    it "reports an exact node match" do
      result = resolver.resolve("Tree Nut")
      expect(result).to have_attributes(match_type: :exact, normalized: "tree nut", similarity: nil,
        reason: "exact match to 'tree nut'")
      expect(result).to be_resolved
      expect(result).not_to be_fuzzy
    end

    it "keeps the original input" do
      expect(resolver.resolve("  No Nuts! ").input).to eq("  No Nuts! ")
    end

    it "resolves an alias and says which alias matched" do
      result = resolver.resolve("almond flour")
      expect(result).to have_attributes(node: node("almond"), match_type: :alias,
        reason: "alias 'almond flour' → 'almond'")
      expect(node("tree nut").covers?(result.node)).to be(true)
    end

    it "resolves 'no nuts', 'tree nuts' and 'almond flour' into one tree" do
      tree_nut = node("tree nut")
      nodes = resolver.resolve_all([ "no nuts", "tree nuts", "almond flour" ]).map(&:node)
      expect(nodes.first(2)).to all(eq(tree_nut))
      expect(tree_nut.covers?(nodes.last)).to be(true)
    end

    it "singularizes plurals without calling them fuzzy" do
      result = resolver.resolve("almonds")
      expect(result).to have_attributes(node: node("almond"), match_type: :exact,
        reason: "exact match to 'almond' (from 'almonds')")
    end

    it "singularizes plural aliases" do
      expect(resolver.resolve("prawns")).to have_attributes(node: node("shrimp"), match_type: :alias)
    end

    it "matches a misspelling fuzzily and says so" do
      result = resolver.resolve("almnd")
      expect(result.node).to eq(node("almond"))
      expect(result).to be_fuzzy
      expect(result.match_type).to eq(:fuzzy)
      expect(result.similarity).to be_between(described_class::FUZZY_THRESHOLD, 1.0)
      expect(result.reason).to match(/\Afuzzy match to 'almond' \(similarity 0\.\d\d\)\z/)
    end

    it "matches fuzzily against aliases and names the alias" do
      result = resolver.resolve("marzpan")
      expect(result).to have_attributes(node: node("almond"), match_type: :fuzzy)
      expect(result.reason).to include("via alias 'marzipan'")
    end

    %w[cashw shrmp].each do |typo|
      it "marks #{typo.inspect} as fuzzy" do
        expect(resolver.resolve(typo)).to be_fuzzy
      end
    end

    it "does not resolve peanut to tree nut" do
      result = resolver.resolve("peanut")
      expect(result.node).to eq(node("peanut"))
      expect(node("tree nut").covers?(result.node)).to be(false)
      expect(resolver.covers?(node("tree nut"), result.node)).to be(false)
    end

    it "does not treat peanut butter as a tree nut or dairy" do
      result = resolver.resolve("peanut butter")
      expect(result.node).to eq(node("peanut"))
      expect(node("milk").covers?(result.node)).to be(false)
    end

    %w[xyzzy qwrtp zzzzzz].each do |gibberish|
      it "returns an explicit unresolved result for #{gibberish.inspect}" do
        result = resolver.resolve(gibberish)
        expect(result).to have_attributes(node: nil, match_type: :unresolved, similarity: nil,
          reason: "'#{gibberish}' not recognized")
        expect(result).not_to be_resolved
        expect(result).to be_unresolved
        expect(result).not_to be_fuzzy
      end
    end

    it "does not fuzzy-match a near miss below the threshold" do
      expect(resolver.resolve("wheet")).to be_unresolved
    end

    [ nil, "", "   ", "!!!", " - " ].each do |blank|
      it "treats #{blank.inspect} as an empty ingredient" do
        expect(resolver.resolve(blank)).to have_attributes(node: nil, match_type: :unresolved,
          reason: "empty ingredient")
      end
    end

    it "resolves other allergens and their hidden forms" do
      {
        "dairy-free" => "milk", "Eggs" => "egg", "worcestershire" => "worcestershire sauce",
        "crustacean shellfish" => "shellfish", "tahini" => "tahini", "soy lecithin" => "soy lecithin",
        "Natural Flavors" => "natural flavors", "broth" => "stock", "celiac" => "gluten"
      }.each { |text, name| expect(resolver.resolve(text).node).to eq(node(name)), text }
    end
  end

  describe "#resolve_all" do
    it "returns one result per input, in order, including unresolved ones" do
      results = resolver.resolve_all([ "almonds", "xyzzy", nil, "Butter" ])
      expect(results.map(&:match_type)).to eq(%i[exact unresolved unresolved exact])
      expect(results.map { |r| r.node&.name }).to eq([ "almond", nil, nil, "butter" ])
    end

    it "batches the exact lookups" do
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        resolver.resolve_all([ "milk", "almond flour", "tree nuts", "egg", "whey" ])
      end
      expect(queries).to be <= 3
    end

    it "returns an empty array for no input" do
      expect(resolver.resolve_all([])).to eq([])
    end
  end

  describe "phrase scan (contained)" do
    def contained(text) = resolver.resolve(text).contained.map { |found, phrase| [ found.name, phrase ] }

    {
      "toasted sliced almonds" => [ [ "almond", "almonds" ] ],
      "roasted almonds" => [ [ "almond", "almonds" ] ],
      "almond-crusted tilapia" => [ [ "almond", "almond" ], [ "tilapia", "tilapia" ] ],
      "egg noodles" => [ [ "egg", "egg" ] ],
      "grated parmesan cheese" => [ [ "parmesan", "parmesan" ], [ "cheese", "cheese" ] ],
      "low-sodium soy sauce" => [ [ "sodium", "low-sodium" ], [ "soy sauce", "soy sauce" ] ],
      "shrimp stock" => [ [ "shrimp", "shrimp" ], [ "stock", "stock" ] ],
      "peanut butter cookies" => [ [ "peanut", "peanut butter" ] ],
      "cream of tartar" => [ [ "cream", "cream" ] ],
      "all-purpose flour blend" => [ [ "flour", "all-purpose flour" ] ],
      "chopped xyzzy" => []
    }.each do |text, expected|
      it "finds #{expected.map(&:first).inspect} in #{text.inspect}" do
        expect(contained(text)).to eq(expected)
      end
    end

    it "only scans when the whole phrase is fuzzy or unresolved" do
      expect(resolver.resolve("roasted almonds")).to be_unresolved
      expect(resolver.resolve("low-sodium soy sauce")).to be_fuzzy
      %w[almond\ milk soy\ sauce fish\ sauce peanut\ butter Butter].each do |text|
        result = resolver.resolve(text)
        expect(result.match_type).to be_in(%i[exact alias])
        expect(result.contained).to eq([])
      end
    end

    it "uses no fuzzy matching inside the scan" do
      expect(contained("roastd almnds")).to eq([])
    end

    it "takes the longest match and never overlaps (peanut butter, not butter)" do
      expect(contained("peanut butter cookies").map(&:first)).not_to include("butter")
    end

    it "lists each node once" do
      expect(contained("shredded cheddar cheese")).to eq([ [ "cheese", "cheddar" ] ])
    end

    it "adds no queries for the scan: the batched lookups plus the fuzzy ones" do
      phrases = [ "toasted sliced almonds with a little extra sea salt", "low-sodium soy sauce", "egg noodles",
        "grated parmesan cheese", "milk", "almond flour" ]
      queries = 0
      counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
      results = nil
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { results = resolver.resolve_all(phrases) }

      loose = results.count { |result| !result.match_type.in?(%i[exact alias]) }
      expect(loose).to eq(4)
      # nodes, aliases, alias nodes; then two fuzzy queries per loose phrase.
      expect(queries).to eq(3 + (2 * loose))
      expect(results.first.contained.map { |found, _| found.name }).to eq([ "almond", "sodium" ])
    end
  end

  describe "coverage" do
    it "covers dairy and gluten families" do
      { "gluten" => %w[wheat barley rye malt flour], "milk" => %w[lactose whey butter cheese],
        "fish" => %w[anchovy worcestershire\ sauce], "tree nut" => %w[almond brazil\ nut] }.each do |parent, kids|
        kids.each { |kid| expect(resolver.covers?(node(parent), node(kid))).to be(true), "#{parent} → #{kid}" }
      end
    end

    it "lets a lactose intolerance cover milk and everything under it" do
      %w[milk whey cheese butter].each { |kid| expect(resolver.covers?(node("lactose"), node(kid))).to be(true), kid }
    end

    it "does not cover across families" do
      expect(resolver.covers?(node("milk"), node("wheat"))).to be(false)
      expect(resolver.covers?(node("lactose"), node("wheat"))).to be(false)
      expect(resolver.covers?(node("wheat"), node("barley"))).to be(false)
    end

    it "never covers a missing node" do
      expect(resolver.covers?(nil, node("milk"))).to be(false)
      expect(resolver.covers?(node("milk"), nil)).to be(false)
    end
  end
end
