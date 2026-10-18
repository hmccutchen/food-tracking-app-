require "rails_helper"

RSpec.describe "Removing meal suggestion cards" do
  let(:user) { create(:user) }
  let(:turbo_stream) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  before { sign_in(user) }

  def finished_request(**attrs)
    create(:meal_request, user:, status: "found", **attrs).tap { |request| create(:meal_suggestion, meal_request: request) }
  end

  it "shows Remove on finished cards and Clear all on the list, but not on a card still finding meals" do
    finished = finished_request
    pending = create(:meal_request, user:, status: "queued")
    get meal_requests_path
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("##{ActionView::RecordIdentifier.dom_id(finished)} form[action='#{meal_request_path(finished)}']")).to be_present
    expect(page.at_css("##{ActionView::RecordIdentifier.dom_id(pending)} form.remove-meal-request")).to be_nil
    expect(response.body).to include("Clear all")
  end

  it "removes one finished card and its suggestions" do
    finished = finished_request
    other = finished_request
    expect { delete meal_request_path(finished), headers: turbo_stream }.to change(MealSuggestion, :count).by(-1)
    expect(response.body).to include(%(action="remove" target="#{ActionView::RecordIdentifier.dom_id(finished)}"))
    expect(MealRequest.where(id: [ finished.id, other.id ]).pluck(:id)).to eq([ other.id ])
  end

  it "shows the empty state when the last card goes" do
    delete meal_request_path(finished_request), headers: turbo_stream
    expect(response.body).to include("No meal suggestions yet.")
  end

  it "keeps a card that is still finding meals, so its job has somewhere to write" do
    pending = create(:meal_request, user:, status: "running")
    delete meal_request_path(pending), headers: turbo_stream
    expect(MealRequest.exists?(pending.id)).to be(true)
  end

  it "clears every finished card, leaving ones still finding meals and other nurses' cards" do
    2.times { finished_request }
    pending = create(:meal_request, user:, status: "queued")
    someone_else = create(:meal_request, status: "found")
    delete clear_meal_requests_path, headers: turbo_stream
    expect(MealRequest.pluck(:id)).to contain_exactly(pending.id, someone_else.id)
  end

  it "can't remove another nurse's card" do
    someone_else = create(:meal_request, status: "found")
    delete meal_request_path(someone_else), headers: turbo_stream
    expect(response).to have_http_status(:not_found)
    expect(MealRequest.exists?(someone_else.id)).to be(true)
  end
end
