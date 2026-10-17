# Preparation methods that can bring in restricted ingredients the ingredient
# list doesn't show. Loaded by db/seeds.rb after the taxonomy. Advisory only:
# these notes never change an evaluation tier.
#
# Wording: the app shows "Lower-risk method: <lower_risk_method> — <caveat>".
# Never promise anything; every method needs a caveat.
#
# Idempotent and create-only: a method that already exists (by name) is left
# exactly as the nurse last edited it, risk nodes included.
module PrepMethodSeedData
  METHODS = [
    { name: "frying", keywords: %w[fried fry fries deep-fried pan-fried tempura crispy battered],
      risk: "Fryer oil is often shared with breaded or shellfish items, and batter often has wheat, egg or soy.",
      lower_risk_method: "bake or pan-sear in fresh oil", caveat: "still check shared pans and utensils",
      risks: [ "shellfish", "wheat", "fish", "soy", "peanut" ] },
    { name: "breading", keywords: %w[breaded breading crusted panko schnitzel cutlet],
      risk: "Breading usually means wheat flour or crumbs held on with egg or milk.",
      lower_risk_method: "season and roast without a coating",
      caveat: "still check the seasoning label and shared trays",
      risks: [ "wheat", "egg", "milk" ] },
    { name: "marinade", keywords: %w[marinade marinated teriyaki glazed bulgogi satay],
      risk: "Marinades often use soy sauce (soy and wheat), sesame oil or fish sauce.",
      lower_risk_method: "season with herbs, citrus and oil you choose",
      caveat: "still check bottled sauces and shared bowls",
      risks: [ "soy", "wheat", "sesame", "fish" ] },
    { name: "stock or broth", keywords: %w[stock broth bouillon soup stew braised risotto],
      risk: "Stock and broth can hide wheat, milk and a lot of sodium.",
      lower_risk_method: "make stock at home from known ingredients",
      caveat: "still check the label on any cube, base or carton",
      risks: [ "stock", "wheat", "milk" ] },
    { name: "sauce or gravy", keywords: %w[sauce gravy roux creamy alfredo bechamel],
      risk: "Sauces and gravies are often thickened with flour or butter and built on stock.",
      lower_risk_method: "thicken with cornstarch and a stock you have checked",
      caveat: "still check jarred sauces and spice blends",
      risks: [ "wheat", "milk", "stock" ] },
    { name: "baking or pastry", keywords: %w[pastry pastries pie tart cake muffin cookie cookies croissant brownie],
      risk: "Baked goods and pastry usually have wheat, egg and milk, and bakeries often handle tree nuts.",
      lower_risk_method: "bake at home from a recipe you have checked",
      caveat: "still check flour, chocolate and mix labels for may-contain warnings",
      risks: [ "wheat", "egg", "milk", "tree nut" ] },
    { name: "stir-fry or wok", keywords: [ "stir-fry", "stir-fried", "wok", "pad thai", "lo mein", "fried rice" ],
      risk: "Wok dishes often use soy sauce, peanut or sesame oil, and a wok shared with shellfish.",
      lower_risk_method: "stir-fry in a clean pan with an oil you choose",
      caveat: "still check sauces and shared utensils",
      risks: [ "soy", "peanut", "sesame", "shellfish" ] },
    { name: "grilling", keywords: %w[grilled grill barbecue barbecued bbq charbroiled],
      risk: "Shared grill grates often carry residue from shellfish and fish.",
      lower_risk_method: "grill on clean foil or a dedicated pan",
      caveat: "still check shared tongs, brushes and marinades",
      risks: [ "shellfish", "fish" ] }
  ].freeze

  module_function

  def load!(methods = METHODS)
    PrepMethod.transaction do
      methods.each_with_index do |spec, index|
        method = PrepMethod.find_or_initialize_by(name: spec[:name])
        next if method.persisted?

        method.assign_attributes(spec.except(:risks).merge(position: index))
        method.risk_nodes = spec[:risks].map { |name| TaxonomyNode.find_by!(name:) }
        method.save!
      end
    end
  end
end
