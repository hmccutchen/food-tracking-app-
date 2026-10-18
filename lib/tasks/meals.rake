namespace :meals do
  desc "Run the sample meal requests (config/meal_samples.yml) against gemini|anthropic|openai|all (default all). " \
       "Keys and models come from MEAL_SAMPLES_<PROVIDER>_KEY / _MODEL"
  task :samples, [ :provider ] => :environment do |_task, args|
    MealSamples::Runner.new.call(args[:provider].presence || "all")
  rescue MealSamples::Runner::UnknownProviderError => e
    abort e.message
  end
end
