require Rails.root.join("db/seeds/nurse").to_s
NurseSeed.load!

Taxonomy::Seed.load!

require Rails.root.join("db/seeds/prep_methods").to_s
PrepMethodSeedData.load!

# One line for deploy logs: counts and yes/no only, never names or secrets.
puts "Seeded: #{TaxonomyNode.count} taxonomy nodes, #{PrepMethod.count} prep methods, " \
  "#{IngredientDescriptor.count} descriptor words; nurse account #{User.exists?(email: NurseSeed.email) ? 'present' : 'MISSING'}"
