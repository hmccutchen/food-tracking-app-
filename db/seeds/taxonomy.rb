# Ingredient taxonomy: the FDA top 9 allergens, common intolerances, and
# ambiguous label terms. Loaded by Taxonomy::Seed.load! (db/seeds.rb and specs).
#
# Each entry: "name" => { kind:, aliases: [], children: {}, members: [] }. kind
# defaults to :ingredient. Names and aliases are normalized on save, and every
# alias must be unique across the whole tree.
#
# A node has exactly one tree parent. `members:` lists nodes that live elsewhere
# in the tree but also belong to this group (soy sauce stays under soy and is a
# member of sodium). Members must be defined somewhere in TREE.
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
        "cheese" => {
          aliases: [ "cheddar", "mozzarella", "cream cheese", "cottage cheese", "ricotta" ],
          children: { "parmesan" => { aliases: [ "parmigiano", "parmigiano reggiano" ] } }
        },
        "cream" => { aliases: [ "heavy cream", "sour cream", "half and half", "ice cream", "whipped cream" ] },
        "whey" => { aliases: [ "whey protein", "whey powder" ] },
        "casein" => { aliases: [ "caseinate", "sodium caseinate", "calcium caseinate" ] },
        "yogurt" => { aliases: [ "yoghurt", "greek yogurt" ] },
        "ghee" => { aliases: [ "clarified butter" ] },
        # Lactose sits under milk (a milk allergy covers it) and also lists milk
        # as a member, so a lactose intolerance covers milk and everything under it.
        "lactose" => { kind: :intolerance, aliases: [ "lactose intolerance", "lactose intolerant", "milk sugar" ],
                       members: [ "milk" ] }
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
        "tilapia" => {},
        "trout" => {},
        "halibut" => {},
        "sardine" => {},
        "mackerel" => {},
        "catfish" => {},
        "haddock" => {},
        "pollock" => {},
        "snapper" => {},
        "mahi mahi" => {},
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
    },
    "cured meat" => {
      aliases: [ "processed meat", "deli meat", "lunch meat", "salami", "prosciutto", "pepperoni" ],
      children: {
        "bacon" => { aliases: [ "pancetta" ] },
        "ham" => {}
      }
    },
    "pickles" => { aliases: [ "pickle", "dill pickle", "gherkin" ] },
    "olives" => { aliases: [ "olive", "kalamata olive" ] },
    "banana" => {},
    "potato" => { aliases: [ "potatoes", "french fries", "fries" ] },
    "tomato" => { aliases: [ "tomatoes", "tomato sauce", "tomato paste" ] },
    "orange" => { aliases: [ "orange juice" ] },
    "avocado" => { aliases: [ "guacamole" ] },
    "spinach" => {},
    # Conditions. Nutrient groups resolve condition restrictions ("low sodium",
    # "diabetic", "renal diet") through the same resolver.
    #
    # "salt" and "sugar" are aliases of their group rather than child nodes:
    # the normalizer turns "no salt" into "salt" and "no sugar" into "sugar", and
    # those must mean the whole group (soy sauce, honey...), not one ingredient.
    "sodium" => {
      kind: :nutrient,
      aliases: [ "low sodium", "low salt", "salt restriction", "hypertension", "high blood pressure", "heart failure",
                 "salt", "table salt", "sea salt", "kosher salt" ],
      members: [ "soy sauce", "fish sauce", "stock", "cured meat", "bacon", "ham", "pickles", "olives", "parmesan" ]
    },
    "added sugar" => {
      kind: :nutrient,
      aliases: [ "low sugar", "diabetes", "diabetic", "sugar", "cane sugar", "brown sugar", "white sugar",
                 "powdered sugar" ],
      children: {
        "honey" => {},
        "maple syrup" => {},
        "corn syrup" => { aliases: [ "high fructose corn syrup" ] },
        "molasses" => {},
        "agave" => { aliases: [ "agave nectar", "agave syrup" ] }
      }
    },
    "potassium" => {
      kind: :nutrient,
      aliases: [ "low potassium", "renal diet", "kidney disease", "ckd", "chronic kidney disease" ],
      members: [ "banana", "potato", "tomato", "orange", "avocado", "spinach" ]
    }
  }.freeze
end
