require "rails_helper"

RSpec.describe "config/database.yml production URLs" do
  def production_urls(database_url)
    previous = ENV["DATABASE_URL"]
    ENV["DATABASE_URL"] = database_url
    yaml = ERB.new(Rails.root.join("config/database.yml").read).result
    YAML.safe_load(yaml, aliases: true).fetch("production").transform_values { |config| config["url"] }
  ensure
    ENV["DATABASE_URL"] = previous
  end

  it "points cache, queue and cable at their own databases on the same server" do
    urls = production_urls("postgresql://postgres:secret@db.internal:5432/railway?sslmode=require")

    expect(urls["primary"]).to eq("postgresql://postgres:secret@db.internal:5432/railway?sslmode=require")
    expect(urls["queue"]).to eq("postgresql://postgres:secret@db.internal:5432/meal_planner_queue?sslmode=require")
    expect(urls["cache"]).to end_with("/meal_planner_cache?sslmode=require")
    expect(urls["cable"]).to end_with("/meal_planner_cable?sslmode=require")
  end

  it "still produces valid URLs when DATABASE_URL has no database name (as in CI)" do
    urls = production_urls("postgres://postgres:postgres@localhost:5432")

    expect(urls["queue"]).to eq("postgres://postgres:postgres@localhost:5432/meal_planner_queue")
    urls.each_value { |url| expect { URI.parse(url) }.not_to raise_error }
  end
end
