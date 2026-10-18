require "rails_helper"

# The nurse must never be told something is "safe". This scans every view and
# model file, excluding nothing.
RSpec.describe "Wording" do
  it "never uses the word 'safe' in app/views or app/models" do
    files = Dir[Rails.root.join("app/{views,models}/**/*")].select { |path| File.file?(path) }
    expect(files).not_to be_empty
    offenders = files.select { |path| File.read(path).match?(/\bsafe\b/i) }
    expect(offenders).to be_empty, "found 'safe' in: #{offenders.join(', ')}"
  end
end
