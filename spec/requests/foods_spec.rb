require "rails_helper"

RSpec.describe "Foods" do
  let(:user) { create(:user) }
  let(:almond) { create(:taxonomy_node, name: "almond") }

  before { sign_in(user) }

  it "requires sign-in" do
    sign_out
    get foods_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows a search box and a nav link" do
    create(:food)
    get foods_path
    expect(response.body).to include("Search USDA foods", 'turbo-frame id="food_results"', "Search 1 USDA food")
    expect(response.body).to include(%(href="#{foods_path}">Foods</a>))
  end

  it "says when nothing has been imported" do
    get foods_path
    expect(response.body).to include("No USDA foods imported yet")
  end

  it "finds a food despite a typo and describes it in plain words" do
    create(:food, description: "Nuts, almonds", source: "sr_legacy", category: "Nut and Seed Products",
      imported_at: Time.zone.local(2026, 10, 1, 9), taxonomy_node: almond, match_type: "exact",
      match_reason: "matched to almond via 'almonds'")
    create(:food, description: "Pork, loin, boneless, raw")

    get foods_path, params: { q: "almnd" }

    body = response.body
    expect(body).to include("Nuts, almonds", "USDA SR Legacy", "Nut and Seed Products", "imported October 1, 2026")
    expect(body).to include("Ingredient link: matched to almond via &#39;almonds&#39;")
    expect(body).to include("No ingredient list on this record.")
    expect(body).not_to include("Pork, loin")
    expect(body).not_to match(/\bsafe\b/i)
  end

  it "flags a fuzzy link for checking" do
    create(:food, description: "Tamarinds, raw", source: "foundation", taxonomy_node: almond, match_type: "fuzzy",
      match_reason: "fuzzy match to almond via 'tamarinds' (similarity 0.55) — please check")
    get foods_path, params: { q: "tamarind" }
    expect(response.body).to include("USDA Foundation", "Fuzzy match — please check.", "Might be almond")
  end

  it "says when a food is not linked" do
    create(:food, description: "Pork, loin, boneless, raw")
    get foods_path, params: { q: "pork" }
    expect(response.body).to include("Not linked to a known ingredient, so checks treat it as unknown")
  end

  it "says when nothing matches" do
    create(:food)
    get foods_path, params: { q: "zzqxv" }
    expect(response.body).to include("No foods found for “zzqxv”")
  end

  it "escapes the query" do
    create(:food)
    get foods_path, params: { q: "<script>alert(1)</script>" }
    expect(response.body).not_to include("<script>alert(1)</script>")
  end
end
