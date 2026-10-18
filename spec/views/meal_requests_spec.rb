require "rails_helper"

RSpec.describe "meal_requests/_meal_request" do
  before(:context) { load_prep_method_seed! }
  after(:context) { clear_prep_method_seed! }

  let(:user) { create(:user) }
  let(:ann) { create(:patient, user:, display_name: "Ann Lee") }

  before { ann.restrictions.create!(kind: :allergy, term: "shellfish") }

  def render_request(request)
    render partial: "meal_requests/meal_request", locals: { meal_request: request }
    rendered
  end

  it "shows a placeholder that subscribes to the stream and polls while queued or running" do
    %w[queued running].each do |status|
      html = render_request(create(:meal_request, user:, patient_ids: [ ann.id ], status:))
      expect(html).to include("Finding meals…", "turbo-cable-stream-source", 'data-controller="poll"')
    end
  end

  it "shows a kept meal with its ingredients, stored result, advisory notes and the provider's prep notes" do
    request = stored_meal_request(user, [ ann ],
      kept: [ [ "Fried fish", [ "cod", "flour" ], [ "deep-fried in hot oil", "cook to a safe temperature" ] ] ])
    html = render_request(request)

    expect(html).to include("Meals for Ann Lee", "Fried fish", "cod", "flour")
    expect(html).to include("Ann Lee:", 'class="evaluation-result"', "Overall:")
    expect(html).to include("Check shared pans, oil, and cutting boards", "Preparation note (advisory)")
    expect(html).to include("Suggested preparation (from OpenAI)", "deep-fried in hot oil",
      "cook to a lower-risk temperature")
    expect(html).not_to match(/\bsafe\b/i)
    expect(html).not_to include("Out of date", "Re-check", "Now a conflict", "Dropped")
  end

  it "collapses dropped meals under 'Dropped (conflicts found)' with their reasons" do
    request = stored_meal_request(user, [ ann ], kept: [ [ "Rice bowl", [ "rice" ] ] ],
      dropped: [ [ "Shrimp rice", [ "shrimp", "rice" ] ] ])
    html = render_request(request)

    expect(html).to include("<details", "Dropped (conflicts found)", "Shrimp rice")
    expect(html).to match(/shrimp is a shellfish.*\(allergy\)/)
    expect(html.index("Rice bowl")).to be < html.index("Dropped (conflicts found)")
  end

  it "shows a couldn't-find card with the blocking conflicts when nothing fit" do
    request = stored_meal_request(user, [ ann ], dropped: [ [ "Shrimp rice", [ "shrimp", "rice" ] ] ])
    html = render_request(request)

    expect(html).to include("Couldn't find a meal that fits all of these", "What got in the way")
    expect(html).to match(%r{<ul class="blocking-conflicts">\s*<li>shrimp is a shellfish})
  end

  it "shows the plain error for a failed request, linking to AI settings when that is the fix" do
    html = render_request(create(:meal_request, user:, patient_ids: [ ann.id ], status: "failed",
      error_message: "Pick a model for OpenAI in AI settings.", error_code: "model_missing"))
    expect(html).to include("Pick a model for OpenAI in AI settings.", "Open AI settings", "/settings/ai")

    html = render_request(create(:meal_request, user:, patient_ids: [ ann.id ], status: "failed",
      error_message: "Something went wrong. Try again.", error_code: "unexpected"))
    expect(html).to include("Something went wrong. Try again.")
    expect(html).not_to include("Open AI settings")
  end

  it "marks the cards out of date with a Re-check button after a patient changes" do
    request = stored_meal_request(user, [ ann ], kept: [ [ "Rice bowl", [ "rice" ] ] ])
    ann.restrictions.create!(kind: :allergy, term: "rice")

    html = render_request(request.reload)
    expect(html).to include("Out of date — re-check", "Re-check", "/meal-requests/#{request.id}/recheck")
  end

  it "marks a not-found request out of date too" do
    request = stored_meal_request(user, [ ann ], dropped: [ [ "Shrimp rice", [ "shrimp" ] ] ])
    ann.update!(notes: "changed")
    expect(render_request(request.reload)).to include("Out of date — re-check", "Re-check")
  end

  it "keeps a kept meal that became a conflict visible as 'Now a conflict'" do
    request = stored_meal_request(user, [ ann ], kept: [ [ "Rice bowl", [ "rice" ] ] ])
    ann.restrictions.create!(kind: :allergy, term: "rice")
    request.reload.recheck!

    html = render_request(request.reload)
    expect(html).to include("Now a conflict", "Rice bowl", 'data-tier="conflict"')
    expect(html).not_to include("Out of date")
  end
end
