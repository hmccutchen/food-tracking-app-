require "rails_helper"

RSpec.describe "Meal requests" do
  include ActiveJob::TestHelper

  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  let(:user) { create(:user) }
  let!(:ann) { create(:patient, user:, display_name: "Ann Lee") }
  let!(:stranger) { create(:patient, display_name: "Someone Else") }
  let(:turbo_stream) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  before { sign_in(user) }

  describe "POST /meal-requests" do
    it "creates a request for the nurse's own patients, queues the job with ids only, and shows the placeholder" do
      expect do
        post meal_requests_path, params: { patient_ids: [ ann.id, stranger.id ], request_text: " dinner, soft foods " },
          headers: turbo_stream
      end.to change(MealRequest, :count).by(1)

      request = MealRequest.last
      expect(request).to have_attributes(user:, patient_ids: [ ann.id ], request_text: "dinner, soft foods", status: "queued")
      expect(SuggestMealsJob).to have_been_enqueued.with(user.id, request.id)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("Finding meals…", "turbo-cable-stream-source", %(id="meal_request_#{request.id}"))
      expect(response.body).to include(meal_request_path(request))
    end

    it "redirects back to the group without JavaScript" do
      post meal_requests_path, params: { patient_ids: [ ann.id ] }
      expect(response).to redirect_to(group_path(patient_ids: [ ann.id ]))
    end

    it "refuses a request with none of the nurse's patients" do
      expect { post meal_requests_path, params: { patient_ids: [ stranger.id ] } }.not_to change(MealRequest, :count)
      expect(flash[:notice]).to eq("Pick at least one patient first.")
      expect(enqueued_jobs).to be_empty
    end
  end

  describe "GET /meal-requests/:id" do
    it "renders the request's frame (the poll fallback)" do
      request = create(:meal_request, user:, patient_ids: [ ann.id ], status: "running")
      get meal_request_path(request)
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/<turbo-frame [^>]*id="meal_request_#{request.id}"/).and include("Finding meals…")
    end

    it "is a 404 for another nurse's request" do
      other = create(:meal_request, patient_ids: [ stranger.id ])
      get meal_request_path(other)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /meal-requests/:id/recheck" do
    it "re-runs only the engine and shows the new tier" do
      request = stored_meal_request(user, [ ann ], kept: [ [ "Mac and cheese", [ "macaroni", "cheddar cheese" ] ] ])
      ann.restrictions.create!(kind: :allergy, term: "milk")
      expect(MealSuggester).not_to receive(:new)
      expect(Ai::Adapters).not_to receive(:for)
      expect(Ai::CredentialLookup).not_to receive(:for)

      post recheck_meal_request_path(request), headers: turbo_stream

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("Now a conflict", "Mac and cheese")
      expect(response.body).not_to include("Out of date")
      expect(request.kept_suggestions.sole.reload.tier).to eq("conflict")
    end

    it "is a 404 for another nurse's request" do
      other = create(:meal_request, patient_ids: [ stranger.id ], status: "found")
      post recheck_meal_request_path(other)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the Who's eating page" do
    it "shows the suggest form and the last five requests, most recent first" do
      requests = Array.new(6) do |index|
        create(:meal_request, user:, patient_ids: [ ann.id ], status: "failed", error_message: "Error number #{index}",
          created_at: index.hours.ago)
      end
      create(:meal_request, patient_ids: [ stranger.id ], status: "failed", error_message: "Not yours")

      get group_path(patient_ids: [ ann.id ])
      expect(response.body).to include("Suggest meals", "What kind of meal?")
      # The list loads in its own frame, so the (cacheable) group page holds no meal results.
      expect(response.body).to include('id="recent_meal_requests_frame"', 'src="/meal-requests"')
      expect(response.body).not_to include("Error number")

      get meal_requests_path, headers: { "Turbo-Frame" => "recent_meal_requests_frame" }
      shown = response.body.scan(/Error number \d/)
      expect(shown).to eq((0..4).map { |index| "Error number #{index}" })
      expect(response.body).not_to include("Not yours", dom_id_for(requests.last))
    end
  end

  def dom_id_for(record) = ActionView::RecordIdentifier.dom_id(record)
end
