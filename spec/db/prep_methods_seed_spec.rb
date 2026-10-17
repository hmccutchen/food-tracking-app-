require "rails_helper"

RSpec.describe "Preparation method seed" do
  after { clear_prep_method_seed! }

  it "is idempotent and keeps the nurse's edits" do
    load_prep_method_seed!
    count = PrepMethod.count
    risks = PrepMethodRisk.count
    PrepMethod.find_by!(name: "grilling").update!(caveat: "my own caveat")

    PrepMethodSeedData.load!
    expect(PrepMethod.count).to eq(count)
    expect(PrepMethodRisk.count).to eq(risks)
    expect(PrepMethod.find_by!(name: "grilling").caveat).to eq("my own caveat")
  end

  it "loads every method with a caveat, keywords and risk nodes" do
    load_prep_method_seed!
    expect(PrepMethod.pluck(:name)).to include("frying", "breading", "marinade", "stock or broth", "sauce or gravy",
      "baking or pastry", "stir-fry or wok", "grilling")
    PrepMethod.includes(:risk_nodes).find_each do |method|
      expect(method.caveat).to be_present
      expect(method.keywords).not_to be_empty
      expect(method.risk_nodes).not_to be_empty
      expect(method.lower_risk_line).to start_with("Lower-risk method: ")
    end
    expect(PrepMethod.find_by!(name: "frying").risk_nodes.map(&:name))
      .to contain_exactly("shellfish", "wheat", "fish", "soy", "peanut")
  end

  it "never uses the word 'safe' in the seed or the prep note views" do
    files = [ Rails.root.join("db/seeds/prep_methods.rb"), *Rails.root.glob("app/views/{prep_methods,evaluations}/**/*") ]
    offenders = files.select { |path| File.read(path).match?(/\bsafe\b/i) }
    expect(offenders).to be_empty
  end
end
