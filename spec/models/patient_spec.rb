require "rails_helper"

RSpec.describe Patient do
  subject(:patient) { build(:patient) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to have_many(:restrictions) }
  it { is_expected.to validate_presence_of(:display_name) }

  it "starts at profile version 1" do
    expect(create(:patient).profile_version).to eq(1)
  end

  it "returns a profile stamp of id to version" do
    patient = create(:patient)
    expect(patient.profile_stamp).to eq(patient.id => 1)
  end

  describe "encryption" do
    def raw(column, id) = ActiveRecord::Base.connection.select_value("SELECT #{column} FROM patients WHERE id = #{id.to_i}")

    it "stores display_name and notes encrypted, non-deterministically" do
      patient = create(:patient, display_name: "Margaret Okafor", notes: "Lives with her daughter")
      expect(raw(:display_name, patient.id)).not_to include("Margaret")
      expect(raw(:notes, patient.id)).not_to include("daughter")
      expect(patient.reload.display_name).to eq("Margaret Okafor")

      twin = create(:patient, display_name: "Margaret Okafor")
      expect(raw(:display_name, twin.id)).not_to eq(raw(:display_name, patient.id))
    end
  end

  describe "profile version" do
    let!(:patient) { create(:patient) }

    def version = patient.class.where(id: patient.id).pick(:profile_version)

    it "bumps exactly once when the patient is updated" do
      expect { patient.update!(notes: "new note") }.to change { version }.by(1)
      expect(patient.profile_version).to eq(2)
    end

    it "bumps once per update, across several updates" do
      patient.update!(display_name: "A")
      patient.update!(display_name: "B")
      expect(version).to eq(3)
    end

    it "does not bump when nothing changed" do
      expect { patient.update!(display_name: patient.display_name) }.not_to(change { version })
    end

    it "bumps exactly once when a restriction is created" do
      expect { create(:restriction, patient:) }.to change { version }.by(1)
    end

    it "bumps exactly once when a restriction is updated" do
      restriction = create(:restriction, patient:)
      expect { restriction.update!(note: "since childhood") }.to change { version }.by(1)
      expect { restriction.update!(term: "milk", kind: :intolerance) }.to change { version }.by(1)
    end

    it "does not bump when a restriction save changes nothing" do
      restriction = create(:restriction, patient:)
      expect { restriction.update!(note: restriction.note) }.not_to(change { version })
    end

    it "bumps exactly once when a restriction is destroyed" do
      restriction = create(:restriction, patient:)
      expect { restriction.destroy! }.to change { version }.by(1)
    end

    it "bumps atomically, even from a stale copy" do
      stale = described_class.find(patient.id)
      create(:restriction, patient:)
      stale.update!(notes: "edited from an old page")
      expect(version).to eq(3)
    end

    it "updates the profile stamp" do
      create(:restriction, patient:)
      expect(patient.reload.profile_stamp).to eq(patient.id => 2)
    end
  end

  it "deletes its restrictions with it" do
    restriction = create(:restriction)
    restriction.patient.destroy!
    expect(Restriction.exists?(restriction.id)).to be(false)
  end
end
