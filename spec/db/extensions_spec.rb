require "rails_helper"

RSpec.describe "Database extensions" do
  it "has pg_trgm enabled" do
    expect(ActiveRecord::Base.connection.extension_enabled?("pg_trgm")).to be(true)
  end
end
