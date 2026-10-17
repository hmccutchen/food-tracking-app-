require "rails_helper"

RSpec.describe "Active Record Encryption" do
  it "is configured with keys" do
    expect(ActiveRecord::Encryption.config.primary_key).to be_present
    expect(ActiveRecord::Encryption.config.deterministic_key).to be_present
  end
end
