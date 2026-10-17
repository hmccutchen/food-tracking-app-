require "rails_helper"

RSpec.describe Usda::DescriptionMatcher do
  subject(:matcher) { described_class.new }

  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  def node(name) = TaxonomyNode.find_by!(name:)

  {
    "Nuts, almonds" => [ "almond", "exact" ],
    "Nuts, almonds, whole, raw" => [ "almond", "exact" ],
    "Cheese, cheddar" => [ "cheese", "alias" ],
    "Soy sauce made from soy and wheat (shoyu)" => [ "soy sauce", "phrase" ],
    "Beverages, almond milk, unsweetened" => [ "almond", "alias" ],
    "Beverages, almond milk, unsweetened, shelf stable" => [ "almond", "alias" ],
    "Oil, sesame, salad or cooking" => [ "sesame oil", "exact" ],
    "Sauce, fish, ready-to-serve" => [ "fish sauce", "exact" ],
    "Milk, whole, 3.25% milkfat, with added vitamin D" => [ "milk", "exact" ],
    "Peanut butter, creamy" => [ "peanut", "alias" ],
    "Flour, wheat, all-purpose, enriched, bleached" => [ "wheat", "alias" ],
    "Crustaceans, shrimp, raw" => [ "shrimp", "exact" ],
    "Nuts, pistachio nuts, raw" => [ "pistachio", "phrase" ],
    "Seeds, sesame seeds, whole, dried" => [ "sesame", "alias" ],
    "Bananas, raw" => [ "banana", "exact" ],
    "Honey" => [ "honey", "exact" ],
    "Potatoes, boiled, cooked in skin, flesh, without salt" => [ "potato", "alias" ],
    "Fish, mahimahi, raw" => [ "fish", "exact" ],
    "Tamarinds, raw" => [ "soy sauce", "fuzzy" ],
    "Pork, loin, boneless, raw" => [ nil, "unresolved" ],
    "Pork, fresh, loin, whole, separable lean only, raw" => [ nil, "unresolved" ]
  }.each do |description, (name, match_type)|
    it "links #{description.inspect} to #{name || 'nothing'} (#{match_type})" do
      match = matcher.match(description)
      expect(match.match_type).to eq(match_type)
      expect(match.node).to eq(name && node(name))
    end
  end

  it "explains exact and alias links in plain words" do
    expect(matcher.match("Nuts, almonds").reason).to eq("matched to almond via 'almonds'")
    expect(matcher.match("Cheese, cheddar").reason).to eq("matched to cheese via 'cheddar'")
  end

  it "names the other ingredients a phrase match found" do
    expect(matcher.match("Soy sauce made from soy and wheat (shoyu)").reason)
      .to eq("matched to soy sauce via 'soy sauce' in the description (also mentions soy and wheat)")
  end

  it "never links fuzzily without saying so" do
    match = matcher.match("Tamarinds, raw")
    expect(match).to be_fuzzy
    expect(match).not_to be_linked
    expect(match.reason).to match(/\Afuzzy match to soy sauce via 'tamarinds' \(similarity 0\.\d\d\) — please check\z/)
  end

  it "prefers an exact match on a broader segment over a fuzzy match on a narrower one" do
    # "mahimahi" only fuzzily matches "mahi mahi"; "fish" is exact.
    expect(matcher.match("Fish, mahimahi, raw").reason).to eq("matched to fish via 'fish'")
  end

  it "ignores qualifier segments such as 'without salt'" do
    expect(matcher.candidates("Potatoes, boiled, without salt").all).to eq([ "potatoes boiled", "boiled potatoes", "boiled", "potatoes" ])
    expect(matcher.match("Butter, without salt").node).to eq(node("butter"))
  end

  it "says why an unresolvable description has no link" do
    match = matcher.match("Pork, loin, boneless, raw")
    expect(match).to be_unresolved
    expect(match.reason).to eq("no ingredient match for 'Pork, loin, boneless, raw'")
  end

  it "resolves a batch in the order given with a bounded number of queries" do
    descriptions = [ "Honey", "Pork, loin, boneless, raw", "Nuts, almonds", "Honey" ]
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
    matches = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { matcher.match_all(descriptions) }

    expect(matches.map { |match| match.node&.name }).to eq([ "honey", nil, "almond", "honey" ])
    # Exact pass (nodes + aliases) plus one fuzzy pass for the leftovers.
    expect(queries).to be <= 12
  end

  it "uses an exact-only resolver for the first pass without changing Taxonomy::Resolver" do
    # Guards the override: if Resolver#fuzzy is renamed, this fails.
    expect(Taxonomy::Resolver.private_method_defined?(:fuzzy)).to be(true)
    expect(Taxonomy::Resolver.new.resolve("tamarinds").match_type).to eq(:fuzzy)
    exact = described_class::ExactResolver.new.resolve("roasted tamarinds with almonds")
    expect(exact.match_type).to eq(:unresolved)
    expect(exact.contained_nodes).to eq([ node("almond") ])
  end

  it "handles a blank description" do
    expect(matcher.match("").match_type).to eq("unresolved")
  end
end
