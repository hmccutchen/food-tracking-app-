require "rails_helper"

RSpec.describe MealRequest do
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  let(:user) { create(:user) }
  let(:ann) { create(:patient, user:, display_name: "Ann Lee") }
  let(:ben) { create(:patient, user:, display_name: "Ben Okafor") }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:meal_suggestions).dependent(:delete_all) }

  it "needs at least one patient" do
    request = described_class.new(user:, patient_ids: [])
    expect(request).not_to be_valid
    expect(request.errors.full_messages).to eq([ "Pick at least one patient first." ])
  end

  it "encrypts the request text and the blocking conflicts" do
    request = create(:meal_request, user:, request_text: "soft dinner for Ann", blocking_conflicts: [ "milk is milk (allergy)" ])
    row = described_class.connection.select_one("SELECT request_text, blocking_conflicts FROM meal_requests WHERE id = #{request.id}")
    expect(row.values.join).not_to include("soft dinner", "milk")
    expect(request.reload.blocking_conflicts).to eq([ "milk is milk (allergy)" ])
  end

  it "goes out of date when a patient's restrictions change, and a re-check brings it back up to date" do
    request = stored_meal_request(user, [ ann, ben ], kept: [ [ "Mac and cheese", [ "macaroni", "cheddar cheese" ] ] ])
    kept = request.kept_suggestions.sole
    expect(kept.tier).not_to eq("conflict")
    expect(request).not_to be_stale

    ann.restrictions.create!(kind: :allergy, term: "milk")
    request.reload
    expect(request).to be_stale
    expect(request.kept_suggestions.sole).to be_stale

    expect { request.recheck! }.to(change { kept.reload.evaluated_at })
    request.reload
    expect(request).not_to be_stale
    kept = request.kept_suggestions.sole
    expect(kept.tier).to eq("conflict")
    expect(kept).to be_kept
    expect(kept).to be_now_conflict
    expect(kept.profile_versions).to eq(ann.id.to_s => ann.reload.profile_version, ben.id.to_s => ben.reload.profile_version)
  end

  it "re-checks for the patients still on file when one was deleted" do
    request = stored_meal_request(user, [ ann, ben ], kept: [ [ "Soup", [ "carrot" ] ] ])
    ben.destroy!
    request.reload
    expect(request).to be_stale

    request.recheck!
    request.reload
    expect(request).not_to be_stale
    expect(request.kept_suggestions.sole.group_result.patient_results.map(&:patient_id)).to eq([ ann.id ])
  end

  it "recomputes the blocking conflicts of a not-found request" do
    ann.restrictions.create!(kind: :allergy, term: "peanut")
    request = stored_meal_request(user, [ ann ], dropped: [ [ "Peanut toast", [ "peanut butter", "toast" ] ] ])
    expect(request.blocking_conflicts).to include(match(/peanut/))

    ann.restrictions.destroy_all
    Patient.bump_profile_version!(ann.id)
    request.reload.recheck!
    expect(request.reload.blocking_conflicts).to eq([])
  end
end
