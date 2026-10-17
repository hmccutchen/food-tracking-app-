require "rails_helper"
require "rake"

RSpec.describe "usda rake tasks" do
  before(:context) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("usda:import")
    Taxonomy::Seed.load!
  end
  after(:context) { TaxonomyNode.delete_all }

  def run(name, *args)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*args)
  end

  it "imports a folder and prints the summary" do
    path = Rails.root.join("spec/fixtures/files/usda").to_s
    expect { run("usda:import", path) }.to output(/Imported 26 USDA foods.*USDA SR Legacy: 15.*1 unresolved/m).to_stdout
    expect(Food.count).to eq(26)
  end

  it "defaults to db/usda" do
    importer = instance_double(Usda::Importer, call: "summary")
    expect(Usda::Importer).to receive(:new).with(Rails.root.join("db/usda")).and_return(importer)
    expect { run("usda:import") }.to output("summary\n").to_stdout
  end

  it "aborts with a clear message when the folder is missing" do
    expect { run("usda:import", "/nonexistent/usda") }
      .to raise_error(SystemExit).and output("USDA folder not found: /nonexistent/usda\n").to_stderr
  end

  it "relinks existing foods" do
    create(:food, description: "Nuts, almonds")
    expect { run("usda:relink") }.to output(/Relinked 1 USDA foods: 1 changed\. 1 linked/).to_stdout
    expect(Food.last.taxonomy_node.name).to eq("almond")
  end
end
