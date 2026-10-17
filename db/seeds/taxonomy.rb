# Ingredient taxonomy: the FDA top 9 allergens, common intolerances, and
# ambiguous label terms. Loaded by Taxonomy::Seed.load! (db/seeds.rb and specs).
#
# Each entry: "name" => { kind:, aliases: [], children: {} }. kind defaults to
# :ingredient. Names and aliases are normalized on save, and every alias must be
# unique across the whole tree.
#
# Peanut is a legume, not a tree nut: it is its own top-level allergen, and
# "nuts" / "no nuts" resolve to tree nut only.
module TaxonomySeedData
  TREE = {
    "milk" => {
      kind: :allergen,
      aliases: [ "dairy", "milk products", "cow's milk", "cows milk", "milk solids" ],
      children: {
        "butter" => { aliases: [ "butterfat", "butter oil" ] },
        "cheese" => { aliases: [ "cheddar", "mozzarella", "parmesan", "cream cheese", "cottage cheese", "ricotta" ] },
        "cream" => { aliases: [ "heavy cream", "sour cream", "half and half", "ice cream", "whipped cream" ] },
        "whey" => { aliases: [ "whey protein", "whey powder" ] },
        "casein" => { aliases: [ "caseinate", "sodium caseinate", "calcium caseinate" ] },
        "yogurt" => { aliases: [ "yoghurt", "greek yogurt" ] },
        "ghee" => { aliases: [ "clarified butter" ] },
        "lactose" => { kind: :intolerance, aliases: [ "lactose intolerance", "lactose intolerant", "milk sugar" ] }
      }
    },
    "egg" => {
      kind: :allergen,
      aliases: [ "egg white", "egg yolk", "whole egg", "powdered egg" ],
      children: {
        "mayonnaise" => { aliases: [ "mayo", "aioli" ] },
        "albumin" => { aliases: [ "albumen", "ovalbumin" ] },
        "meringue" => {}
      }
    },
    "fish" => {
      kind: :allergen,
      aliases: [ "finfish" ],
      children: {
        "anchovy" => {
          aliases: [ "anchovy paste" ],
          children: { "worcestershire sauce" => { aliases: [ "worcestershire" ] } }
        },
        "cod" => { aliases: [ "codfish" ] },
        "salmon" => { aliases: [ "smoked salmon", "lox" ] },
        "tuna" => { aliases: [ "canned tuna" ] },
        "fish sauce" => { aliases: [ "nam pla", "nuoc mam" ] }
      }
    },
    "shellfish" => {
      kind: :allergen,
      aliases: [ "crustacean shellfish", "crustacean", "crustaceans" ],
      children: {
        "shrimp" => { aliases: [ "prawn" ] },
        "crab" => { aliases: [ "crabmeat", "crab meat" ] },
        "lobster" => {},
        "crawfish" => { aliases: [ "crayfish", "crawdad" ] }
      }
    },
    "tree nut" => {
      kind: :allergen,
      aliases: [ "nut", "nuts", "tree nuts", "mixed nuts" ],
      children: {
        "almond" => { aliases: [ "almond flour", "almond milk", "almond butter", "almond meal", "marzipan" ] },
        "walnut" => {},
        "pecan" => {},
        "cashew" => { aliases: [ "cashew butter" ] },
        "pistachio" => {},
        "hazelnut" => { aliases: [ "filbert", "nutella" ] },
        "macadamia" => { aliases: [ "macadamia nut" ] },
        "brazil nut" => {}
      }
    },
    "peanut" => {
      kind: :allergen,
      aliases: [ "peanuts", "peanut butter", "peanut oil", "groundnut", "arachis oil" ]
    },
    "gluten" => {
      kind: :category,
      aliases: [ "celiac", "coeliac", "celiac disease", "gluten intolerance" ],
      children: {
        "wheat" => {
          kind: :allergen,
          aliases: [ "wheat flour", "whole wheat", "wheat starch" ],
          children: {
            "flour" => { aliases: [ "all purpose flour", "all-purpose flour", "enriched flour", "white flour" ] },
            "bread crumbs" => { aliases: [ "breadcrumbs", "panko" ] },
            "semolina" => {},
            "durum" => { aliases: [ "durum wheat" ] },
            "farina" => {},
            "spelt" => {},
            "seitan" => { aliases: [ "wheat gluten", "vital wheat gluten" ] },
            "couscous" => {}
          }
        },
        "barley" => { aliases: [ "pearl barley" ] },
        "rye" => { aliases: [ "rye flour" ] },
        "malt" => { aliases: [ "malt extract", "malt vinegar", "barley malt" ] }
      }
    },
    "soy" => {
      kind: :allergen,
      aliases: [ "soya", "soybean", "soy bean", "soy protein", "soy milk" ],
      children: {
        "soy sauce" => { aliases: [ "shoyu", "tamari" ] },
        "tofu" => { aliases: [ "bean curd" ] },
        "edamame" => {},
        "miso" => { aliases: [ "miso paste" ] },
        "tempeh" => {},
        "soy lecithin" => { aliases: [ "soya lecithin" ] }
      }
    },
    "sesame" => {
      kind: :allergen,
      aliases: [ "sesame seed", "sesame seeds" ],
      children: {
        "tahini" => { aliases: [ "tahina", "sesame paste" ] },
        "sesame oil" => {}
      }
    },
    # Vague label terms that may hide an allergen. Later milestones map these to
    # possible_conflict rather than a pass.
    "ambiguous ingredient" => {
      kind: :category,
      children: {
        "natural flavors" => { aliases: [ "natural flavor", "natural flavoring", "natural flavouring", "flavoring" ] },
        "spices" => { aliases: [ "spice", "spice blend" ] },
        "stock" => { aliases: [ "broth", "bouillon" ] },
        "seasoning" => { aliases: [ "seasoning blend", "seasoning mix" ] }
      }
    }
  }.freeze
end
