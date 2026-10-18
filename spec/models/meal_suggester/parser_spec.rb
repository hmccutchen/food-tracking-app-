require "rails_helper"

RSpec.describe MealSuggester::Parser do
  subject(:parser) { described_class.new("gemini") }

  let(:meal) { { "dish" => "Baked cod", "ingredients" => [ "cod fillet", "lemon juice" ], "prep_notes" => [ "Bake 12 minutes." ] } }

  def parse(value) = parser.call(value.is_a?(String) ? value : value.to_json)

  def expect_malformed(value)
    expect { parse(value) }.to raise_error(Ai::MalformedResponseError) { |error|
      expect(error.message).to eq("Google Gemini sent back something we couldn't read. Trying again may help.")
      expect(error.cause).to be_nil
    }
  end

  it "returns suggestions, stripping whitespace, dropping exact duplicates and ignoring extra keys" do
    result = parse("meals" => [ meal.merge("dish" => "  Baked cod ", "ingredients" => [ " cod fillet", "cod fillet", "Cod fillet" ],
                                           "prep_notes" => [ " Bake. ", "" ], "calories" => 400) ], "note" => "hi")
    expect(result).to eq([ MealSuggester::Suggestion.new(dish: "Baked cod", ingredients: [ "cod fillet", "Cod fillet" ], prep_notes: [ "Bake." ]) ])
  end

  it "accepts an empty prep_notes list" do
    expect(parse("meals" => [ meal.merge("prep_notes" => []) ]).first.prep_notes).to eq([])
  end

  it "strips ``` fences and leading or trailing prose" do
    json = { meals: [ meal ] }.to_json
    expect(parse("```json\n#{json}\n```").size).to eq(1)
    expect(parse("Here are some ideas:\n```\n#{json}\n```\nEnjoy!").size).to eq(1)
    expect(parse("Sure! #{json} Let me know.").size).to eq(1)
  end

  describe "rejects as malformed" do
    it("prose with no JSON") { expect_malformed("A warm chicken soup would be lovely.") }
    it("broken JSON") { expect_malformed('{"meals":[{"dish":"Soup","ingredients":["carrot",') }
    it("empty or nil text") { [ "", nil ].each { |text| expect { parser.call(text) }.to raise_error(Ai::MalformedResponseError) } }
    it("a bare array") { expect_malformed([ meal ]) }
    it("a missing or non-array meals key") do
      expect_malformed("recipes" => [ meal ])
      expect_malformed("meals" => meal)
    end
    it("no meals") { expect_malformed("meals" => []) }
    it("more than 5 meals") { expect_malformed("meals" => [ meal ] * 6) }
    it("a meal that isn't an object") { expect_malformed("meals" => [ "Soup" ]) }
    it("a blank or over-long dish") { [ " ", nil, 5, "x" * 121 ].each { |dish| expect_malformed("meals" => [ meal.merge("dish" => dish) ]) } }
    it("ingredients as one string") { expect_malformed("meals" => [ meal.merge("ingredients" => "cod, lemon") ]) }
    it("no ingredients") { expect_malformed("meals" => [ meal.merge("ingredients" => []) ]) }
    it("more than 40 ingredients") { expect_malformed("meals" => [ meal.merge("ingredients" => (1..41).map { |n| "item #{n}" }) ]) }
    it("a blank, non-string or over-long ingredient") do
      [ "  ", 3, { "name" => "cod" }, "x" * 121 ].each { |bad| expect_malformed("meals" => [ meal.merge("ingredients" => [ "cod", bad ]) ]) }
    end
    it("missing or non-array prep_notes") { [ nil, "Bake" ].each { |notes| expect_malformed("meals" => [ meal.merge("prep_notes" => notes) ]) } }
    it("more than 10 prep notes or a non-string note") do
      expect_malformed("meals" => [ meal.merge("prep_notes" => [ "step" ] * 11) ])
      expect_malformed("meals" => [ meal.merge("prep_notes" => [ 1 ]) ])
    end
    it("a huge reply") { expect_malformed("{\"meals\":[#{' ' * 200_001}]}") }
  end

  it "keeps 40 ingredients after duplicates are dropped" do
    ingredients = (1..40).map { |n| "item #{n}" } + [ "item 1" ]
    expect(parse("meals" => [ meal.merge("ingredients" => ingredients) ]).first.ingredients.size).to eq(40)
  end
end
