require Rails.root.join("db/seeds/prep_methods").to_s

# Loads the taxonomy and the default preparation methods (db/seeds/prep_methods.rb).
module PrepMethodSeedHelper
  def load_prep_method_seed!
    Taxonomy::Seed.load!
    PrepMethodSeedData.load!
  end

  def clear_prep_method_seed!
    PrepMethod.delete_all
    TaxonomyNode.delete_all
  end
end

RSpec.configure do |config|
  config.include PrepMethodSeedHelper
end
