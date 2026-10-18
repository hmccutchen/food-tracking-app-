require "rails_helper"
require "rake"

RSpec.describe MealSamples::Runner do
  before(:context) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("meals:samples")
    load_prep_method_seed!
  end
  after(:context) { clear_prep_method_seed! }

  let(:report_dir) { Pathname(Dir.mktmpdir("meal_samples")) }
  after { FileUtils.rm_rf(report_dir) }

  let(:keys) { { "openai" => "sk-SAMPLE-openai-secret-9999", "gemini" => "AIzaSAMPLE-gemini-secret-8888" } }
  let(:env) do
    {
      "MEAL_SAMPLES_OPENAI_KEY" => keys["openai"], "MEAL_SAMPLES_OPENAI_MODEL" => "gpt-test",
      "MEAL_SAMPLES_GEMINI_KEY" => keys["gemini"], "MEAL_SAMPLES_GEMINI_MODEL" => "gemini-test",
      "MEAL_SAMPLES_ANTHROPIC_MODEL" => "claude-test"
    }
  end

  # Every provider gets the same three meals, except that a peanut allergy
  # only ever gets the peanut dish (so every attempt is dropped). Gemini's
  # first reply each sample is unreadable, so it retries once.
  let(:peanut_noodles) { FakeMealAdapter.meal("Peanut noodles", "peanut butter", "rice noodles", "soy sauce") }
  let(:meals) do
    lambda do |prompt|
      next FakeMealAdapter.meals(peanut_noodles) if prompt.terms.include?("peanut")

      FakeMealAdapter.meals(peanut_noodles,
        FakeMealAdapter.meal("Herb chicken", "chicken breast", "olive oil", "zaatar blend"),
        FakeMealAdapter.meal("Fruit bowl", "banana", "blueberries"))
    end
  end
  let(:adapters) { [] }
  let(:factory) do
    lambda do |credential|
      replies = credential.provider == "gemini" ? [ "no json here", meals ] : [ meals ]
      FakeMealAdapter.new(*replies, provider: credential.provider).tap { |adapter| adapters << adapter }
    end
  end
  let(:clock) { (0..).step(0.5).each.then { |ticks| -> { ticks.next } } }
  let(:out) { StringIO.new }

  def runner(**options)
    described_class.new(adapter_factory: factory, env:, out:, report_dir:, clock:, **options)
  end

  it "prints a table per provider, a summary row and the unresolved phrases, then writes Markdown" do
    path = runner.call("all")
    text = out.string
    puts text, path.read if ENV["SHOW_SAMPLES"]

    expect(text).to include("Skipping Anthropic Claude: set MEAL_SAMPLES_ANTHROPIC_KEY to run it.")
    expect(text).to include("== Google Gemini (model gemini-test) ==", "== OpenAI (model gpt-test) ==")
    expect(text.scan(/^dinner_wheat_dairy_sodium /).size).to eq(2)
    expect(text.lines.grep(/^TOTAL/).size).to eq(2)
    expect(text).to match(/^kid_egg_sesame\s+1\s+3\s+3\s+0\s+2\s+0\.0%\s+25\.0%\s+0\s+0\s+0\.5$/)
    expect(text).to match(/^vegetarian_peanut_mushroom\s+3\s+3\s+0\s+3\s+0\s+100\.0%\s+33\.3%\s+0\s+0\s+0\.5$/)
    expect(text).to match(/^lunch_shellfish_soy\s+1\s+3\s+2\s+1\s+1\s+33\.3%/)
    expect(text).to match(/^TOTAL\s+10\s+24\s+18\s+6\s+11\s+25\.0%\s+26\.2%\s+0\s+0\s+4\.0$/)
    expect(text).to match(/Most common unresolved ingredient phrases \(top 25\):\n\s+19\s+rice noodles\n\s+14\s+zaatar blend\n/)

    gemini = text[/== Google Gemini.*?\n\n/m]
    expect(gemini.lines.grep(/^kid_egg_sesame/).sole.split.values_at(1, -3, -2)).to eq(%w[2 1 0])

    expect(path.read).to include("## OpenAI (model gpt-test)", "| **TOTAL** |", "| zaatar blend |")
    expect(path.dirname).to eq(report_dir)
    expect(text).to include("Report written to #{path}")
  end

  it "sends no names and no real keys anywhere it prints or writes" do
    path = runner.call("all")
    keys.each_value { |key| expect(out.string + path.read).not_to include(key) }
    expect(out.string + path.read).not_to include(keys["openai"].last(8))
    expect(adapters.flat_map(&:prompts).map(&:text)).to all(satisfy { |text| !text.match?(/sample [abc]/i) })
  end

  it "rolls back every synthetic patient, restriction and user" do
    expect { runner.call("openai") }.not_to(change { [ User.count, Patient.count, Restriction.count ] })
    expect(adapters.size).to eq(8)
  end

  it "skips a provider without both a key and a model" do
    expect(runner.call("anthropic")).to be_nil
    expect(out.string).to eq("Skipping Anthropic Claude: set MEAL_SAMPLES_ANTHROPIC_KEY to run it.\nNo providers ran.\n")
    expect(adapters).to be_empty
  end

  it "rejects an unknown provider" do
    expect { runner.call("mistral") }.to raise_error(described_class::UnknownProviderError, /gemini, anthropic, openai, all/)
  end

  it "records a crash by class name only" do
    crashing = ->(_credential) { Object.new.tap { |o| def o.complete(_) = raise(ArgumentError, "secret detail") } }
    runner(adapter_factory: crashing).call("openai")
    expect(out.string).to include("dinner_wheat_dairy_sodium (crashed (ArgumentError))")
    expect(out.string).not_to include("secret detail")
  end

  describe "rake meals:samples" do
    # The task builds its own Runner; hand it the fakes (and the captured $stdout).
    def inject_fakes(**overrides)
      allow(described_class).to receive(:new).and_wrap_original do |original|
        original.call(adapter_factory: factory, env:, out: $stdout, report_dir:, clock:, **overrides)
      end
    end

    def run_task(*args)
      task = Rake::Task["meals:samples"]
      task.reenable
      task.invoke(*args)
    end

    it "runs the chosen provider through the runner" do
      inject_fakes
      expect { run_task("openai") }.to output(/== OpenAI \(model gpt-test\) ==.*^TOTAL/m).to_stdout
      expect(Patient.count).to eq(0)
    end

    it "defaults to all providers and prints skip lines without keys" do
      inject_fakes(env: {})
      expect { run_task }.to output(/Skipping Google Gemini: set MEAL_SAMPLES_GEMINI_KEY and MEAL_SAMPLES_GEMINI_MODEL to run it\.\n.*Skipping OpenAI.*No providers ran/m).to_stdout
    end

    it "aborts on an unknown provider" do
      expect { run_task("mistral") }.to raise_error(SystemExit).and output(/Unknown provider "mistral"/).to_stderr
    end
  end
end
