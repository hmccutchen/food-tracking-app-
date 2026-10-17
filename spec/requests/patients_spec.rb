require "rails_helper"

RSpec.describe "Patients" do
  let(:user) { create(:user) }
  let!(:patient) { create(:patient, user:, display_name: "Ada Lovelace") }
  let(:stranger) { create(:patient, display_name: "Someone Else") }

  before { sign_in(user) }

  it "requires sign-in" do
    delete session_path
    get patients_path
    expect(response).to redirect_to(new_session_path)
  end

  it "lists only the nurse's own patients" do
    stranger
    get patients_path
    expect(response.body).to include("Ada Lovelace").and include("Add a patient")
    expect(response.body).not_to include("Someone Else")
  end

  it "creates a patient" do
    expect {
      post patients_path, params: { patient: { display_name: "Grace Hopper", notes: "Prefers soft food" } }
    }.to change(user.patients, :count).by(1)
    expect(response).to redirect_to(user.patients.order(:id).last)
  end

  it "re-renders the form when the name is blank" do
    post patients_path, params: { patient: { display_name: "" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Display name can")
  end

  it "shows a patient with the profile version" do
    get patient_path(patient)
    expect(response.body).to include("Ada Lovelace").and include("Profile v1")
  end

  it "updates a patient and bumps the profile once" do
    patch patient_path(patient), params: { patient: { notes: "Uses a walker" } }
    expect(response).to redirect_to(patient)
    expect(patient.reload).to have_attributes(notes: "Uses a walker", profile_version: 2)
  end

  it "ignores an attempt to set the profile version" do
    patch patient_path(patient), params: { patient: { display_name: "Ada L", profile_version: 99 } }
    expect(patient.reload.profile_version).to eq(2)
  end

  it "destroys a patient" do
    expect { delete patient_path(patient) }.to change(Patient, :count).by(-1)
    expect(response).to redirect_to(patients_path)
  end

  describe "another user's patient" do
    it "returns 404 for show, edit, update and destroy" do
      get patient_path(stranger)
      expect(response).to have_http_status(:not_found)
      get edit_patient_path(stranger)
      expect(response).to have_http_status(:not_found)
      patch patient_path(stranger), params: { patient: { display_name: "Hacked" } }
      expect(response).to have_http_status(:not_found)
      delete patient_path(stranger)
      expect(response).to have_http_status(:not_found)
      expect(stranger.reload.display_name).to eq("Someone Else")
    end
  end
end
