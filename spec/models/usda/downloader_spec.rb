require "rails_helper"
require "open3"

RSpec.describe Usda::Downloader do
  let(:base) { "https://fdc.nal.usda.gov/fdc-datasets/" }
  let(:page) do
    <<~HTML
      <a href="/fdc-datasets/FoodData_Central_foundation_food_csv_2024-10-31.zip">Oct 2024</a>
      <a href="/fdc-datasets/FoodData_Central_foundation_food_csv_2025-12-18.zip">Dec 2025</a>
      <a href="/fdc-datasets/FoodData_Central_foundation_food_json_2025-12-18.zip">JSON</a>
      <a href="/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip">SR Legacy</a>
    HTML
  end
  let(:quiet) { ->(_line) { } }

  def downloader(env = {}) = described_class.new(env:, log: quiet)

  # A zip like USDA's: one top folder holding food.csv and food_category.csv.
  def zip_of_fixture(name)
    Dir.mktmpdir do |dir|
      folder = File.join(dir, name).tap { |path| FileUtils.mkdir_p(path) }
      FileUtils.cp(Dir[Rails.root.join("spec/fixtures/files/usda/*.csv")], folder)
      _out, err, status = Open3.capture3("zip", "-qr", "archive.zip", name, chdir: dir)
      raise err unless status.success?

      File.binread(File.join(dir, "archive.zip"))
    end
  end

  it "reads the newest CSV file names from the download page" do
    stub_request(:get, described_class::PAGE_URL).to_return(body: page)
    expect(downloader.urls).to eq(
      "foundation" => "#{base}FoodData_Central_foundation_food_csv_2025-12-18.zip",
      "sr_legacy" => "#{base}FoodData_Central_sr_legacy_food_csv_2018-04.zip"
    )
  end

  it "falls back to known release files when the page can't be read" do
    stub_request(:get, described_class::PAGE_URL).to_return(status: 503)
    expect(downloader.urls).to eq(described_class::FALLBACKS)
  end

  it "lets USDA_FOUNDATION_URL / USDA_SR_LEGACY_URL choose the files" do
    stub_request(:get, described_class::PAGE_URL).to_return(body: page)
    url = "#{base}FoodData_Central_foundation_food_csv_2025-04-24.zip"
    expect(downloader("USDA_FOUNDATION_URL" => url).urls["foundation"]).to eq(url)
  end

  it "downloads and unzips both archives, ready for the importer" do
    stub_request(:get, described_class::PAGE_URL).to_return(body: page)
    stub_request(:get, "#{base}FoodData_Central_foundation_food_csv_2025-12-18.zip")
      .to_return(status: 302, headers: { "Location" => "/fdc-datasets/mirror/foundation.zip" })
    stub_request(:get, "#{base}mirror/foundation.zip").to_return(body: zip_of_fixture("FoodData_Central_foundation"))
    stub_request(:get, "#{base}FoodData_Central_sr_legacy_food_csv_2018-04.zip")
      .to_return(body: zip_of_fixture("FoodData_Central_sr_legacy"))

    Dir.mktmpdir do |dir|
      folders = downloader.download(dir)
      expect(folders.map { |folder| folder.basename.to_s }).to eq(%w[FoodData_Central_foundation FoodData_Central_sr_legacy])
      expect(folders).to all(satisfy { |folder| folder.join("food.csv").file? })
      expect(Usda::Importer.new(folders.first).call.total).to be > 0
    end
  end

  it "never leaves fdc.nal.usda.gov or HTTPS, even when redirected" do
    stub_request(:get, described_class::PAGE_URL).to_return(body: page)
    stub_request(:get, "#{base}FoodData_Central_foundation_food_csv_2025-12-18.zip")
      .to_return(status: 302, headers: { "Location" => "https://elsewhere.example/evil.zip" })
    Dir.mktmpdir do |dir|
      expect { downloader.download(dir) }.to raise_error(described_class::Error, /only https:\/\/fdc.nal.usda.gov/)
    end
    expect { Dir.mktmpdir { |dir| downloader("USDA_SR_LEGACY_URL" => "http://fdc.nal.usda.gov/x.zip").download(dir) } }
      .to raise_error(described_class::Error)
  end

  it "says which download failed" do
    stub_request(:get, described_class::PAGE_URL).to_return(body: page)
    stub_request(:get, "#{base}FoodData_Central_foundation_food_csv_2025-12-18.zip").to_return(status: 404)
    Dir.mktmpdir do |dir|
      expect { downloader.download(dir) }.to raise_error(described_class::Error, /csv_2025-12-18.zip answered 404/)
    end
  end
end
