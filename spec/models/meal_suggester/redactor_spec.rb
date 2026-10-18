require "rails_helper"

RSpec.describe MealSuggester::Redactor do
  def redact(text, names) = described_class.call(text, names)

  it "replaces full names and name parts, case-insensitively, as whole words" do
    expect(redact("Dinner for ANN LEE; ann likes fish, Lee doesn't", [ "Ann Lee" ]))
      .to eq("Dinner for the patient; the patient likes fish, the patient doesn't")
  end

  it "leaves words that only contain a name alone" do
    expect(redact("Annie wants a banana and leeks", [ "Ann Lee" ])).to eq("Annie wants a banana and leeks")
  end

  it "handles possessives, punctuation and regex characters in names" do
    expect(redact("Mr. O'Brien's lunch (O'Brien)", [ "Mr. O'Brien" ])).to eq("the patient's lunch (the patient)")
    expect(redact("for J.R.", [ "J.R." ])).to eq("for the patient.")
  end

  it "redacts single-letter names" do
    expect(described_class.call("Dinner for Q, no nuts", [ "Q" ])).to eq("Dinner for the patient, no nuts")
  end

  it "redacts each part of a hyphenated name, and the hyphenated name itself" do
    names = [ "Mary-Jane Smith" ]
    expect(described_class.call("Dinner for Mary", names)).to eq("Dinner for the patient")
    expect(described_class.call("Lunch for Mary-Jane", names)).to eq("Lunch for the patient")
    expect(described_class.call("Snack for Jane Smith", names)).not_to match(/jane|smith|mary/i)
  end

  it "redacts names in scripts written without spaces, even when joined to other words" do
    expect(described_class.call("给李做晚饭", [ "李" ])).to eq("给the patient做晚饭")
    expect(described_class.call("晚饭给王小明", [ "王小明" ])).to eq("晚饭给the patient")
    expect(described_class.call("민수에게 저녁", [ "민수" ])).to eq("the patient에게 저녁")
  end

  it "matches straight and curly apostrophes to each other" do
    expect(described_class.call("Dinner for O’Brien", [ "Ann O'Brien" ])).to eq("Dinner for the patient")
    expect(described_class.call("Dinner for O'Brien", [ "Ann O’Brien" ])).to eq("Dinner for the patient")
  end

  it "does nothing without names" do
    expect(redact("soft foods", [])).to eq("soft foods")
    expect(redact("soft foods", [ "", nil ])).to eq("soft foods")
  end
end
