require "rails_helper"
require Rails.root.join("db/seeds/nurse").to_s

RSpec.describe NurseSeed do
  let(:env) { { "NURSE_EMAIL" => " Nurse@Example.com ", "NURSE_PASSWORD" => "first-deploy-password" } }

  def seed(extra = {}, local: false)
    described_class.load!(env: env.merge(extra), local:)
  end

  it "creates the nurse from NURSE_EMAIL and NURSE_PASSWORD" do
    seed
    expect(User.sole).to have_attributes(email: "nurse@example.com")
    expect(User.sole.valid_password?("first-deploy-password")).to be(true)
  end

  it "leaves a password changed in the app alone on later deploys" do
    seed
    User.sole.update!(password: "changed-on-account-page")
    seed({ "NURSE_PASSWORD" => "a-different-env-value" })
    expect(User.sole.valid_password?("changed-on-account-page")).to be(true)
  end

  it "resets the password only when NURSE_RESET_PASSWORD=1" do
    seed
    expect { seed({ "NURSE_PASSWORD" => "the-reset-password", "NURSE_RESET_PASSWORD" => "1" }) }
      .to output(/Nurse password reset/).to_stdout
    expect(User.sole.valid_password?("the-reset-password")).to be(true)
  end

  it "has no default password outside development and test" do
    expect { seed({ "NURSE_PASSWORD" => nil }) }.to output(/Skipping the nurse account/).to_stderr
    expect(User.count).to eq(0)
  end
end
