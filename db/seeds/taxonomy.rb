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
      aliases: [ "dairy", "milk products", "cow's milk", "cows milk", "milk solids", "whole milk", "skim milk",
                 "nonfat milk", "low fat milk", "evaporated milk", "condensed milk", "goat milk", "goat's milk" ],
      children: {
        "butter" => { aliases: [ "butterfat", "butter oil" ] },
        "cheese" => {
          aliases: [ "cheddar", "mozzarella", "cream cheese", "cottage cheese", "ricotta", "feta", "goat cheese",
                     "swiss cheese", "provolone", "monterey jack", "gouda" ],
          children: { "parmesan" => { aliases: [ "parmigiano", "parmigiano reggiano" ] } }
        },
        "cream" => { aliases: [ "heavy cream", "sour cream", "half and half", "ice cream", "whipped cream",
                                "whipping cream", "heavy whipping cream" ] },
        "buttermilk" => {},
        "kefir" => {},
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
        "sea bass" => {},
        "swordfish" => {},
        "flounder" => {},
        "herring" => {},
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
        "almond" => { aliases: [ "almond flour", "almond milk", "almond butter", "almond meal", "marzipan",
                                 "almond oil", "almond extract" ] },
        "walnut" => { aliases: [ "walnut oil" ] },
        "pecan" => {},
        "cashew" => { aliases: [ "cashew butter" ] },
        "pistachio" => {},
        "hazelnut" => { aliases: [ "filbert", "nutella", "hazelnut oil" ] },
        "macadamia" => { aliases: [ "macadamia nut" ] },
        "brazil nut" => {},
        # The FDA lists pine nut and chestnut as tree nuts. Coconut is no longer
        # listed and lives under common food instead.
        "pine nut" => { aliases: [ "pignoli", "pignolia", "pinon nut" ] },
        "chestnut" => {}
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
          # Most soy sauce is brewed with wheat. Tamari (an alias) is often
          # wheat-free but not always, so it is flagged too: worst case wins.
          members: [ "soy sauce" ],
          children: {
            "flour" => { aliases: [ "all purpose flour", "all-purpose flour", "enriched flour", "white flour" ] },
            "bread crumbs" => { aliases: [ "breadcrumbs", "panko" ] },
            "semolina" => {},
            "durum" => { aliases: [ "durum wheat" ] },
            "farina" => {},
            "spelt" => {},
            "seitan" => { aliases: [ "wheat gluten", "vital wheat gluten" ] },
            "couscous" => {},
            "bulgur" => { aliases: [ "bulgur wheat", "bulghur" ] },
            "farro" => { aliases: [ "emmer" ] },
            "kamut" => { aliases: [ "khorasan wheat" ] },
            "einkorn" => {},
            "wheat germ" => {},
            "wheat bran" => {},
            "wheat berry" => { aliases: [ "wheat berries" ] }
          }
        },
        "barley" => { aliases: [ "pearl barley" ] },
        "rye" => { aliases: [ "rye flour" ] },
        "malt" => { aliases: [ "malt extract", "malt vinegar", "barley malt" ] },
        "triticale" => {}
      },
      # Oats have no gluten of their own but are very often cross-contaminated
      # with wheat, so the gluten group covers them (conservative; a nurse can
      # add a "can" for certified gluten-free oats). A wheat allergy does not.
      members: [ "oat" ]
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
        "soy lecithin" => { aliases: [ "soya lecithin" ] },
        "soybean oil" => { aliases: [ "soy oil", "soya oil" ] },
        "natto" => {}
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
        "seasoning" => { aliases: [ "seasoning blend", "seasoning mix" ] },
        # A canned, sauced product, not plain beans: often sweetened and sometimes
        # made with pork or wheat. Listed here so "baked" as a descriptor can't
        # turn it into a plain bean.
        "baked beans" => { aliases: [ "pork and beans", "canned baked beans" ] }
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
    "orange" => { aliases: [ "orange juice", "orange zest" ] },
    "avocado" => { aliases: [ "guacamole" ] },
    "spinach" => {},
    # Common whole foods, so a plain "chicken breast" or "blueberries" is
    # recognized and checked instead of reading as unknown. Recognized is not
    # the same as no flags: every node here is still checked against each
    # restriction, through the tree and through group memberships.
    #
    # Rules for this block: single whole foods only. Mixed or processed items
    # (sauces, breads, noodles, pasta, sausages, seasoning or spice blends,
    # curry paste, broth, dressing) stay out so they read as unknown unless the
    # scan finds an allergen in them. Anything allergen-related lives under its
    # allergen instead (peanut oil → peanut, nuts → tree nut, wheat grains →
    # wheat, butter → milk, soybean oil → soy, sesame oil → sesame; oats are a
    # member of gluten). Sub-category names start with "common" so an AI phrase
    # like "legumes" or "vegetables" never matches a whole group exactly.
    "common food" => {
      kind: :category,
      children: {
        "common poultry" => {
          kind: :category,
          children: {
            "chicken" => { aliases: [ "chicken breast", "chicken thigh", "chicken leg", "chicken drumstick",
                                      "chicken wing", "whole chicken", "chicken tenderloin" ] },
            "turkey" => { aliases: [ "turkey breast", "turkey thigh" ] },
            "duck" => { aliases: [ "duck breast" ] },
            "goose" => {},
            "quail" => {},
            "cornish hen" => { aliases: [ "cornish game hen" ] }
          }
        },
        "common meats" => {
          kind: :category,
          children: {
            "beef" => { aliases: [ "steak", "beef steak", "sirloin", "sirloin steak", "flank steak", "ribeye",
                                   "beef chuck", "chuck roast", "brisket", "beef brisket", "beef tenderloin" ] },
            "pork" => { aliases: [ "pork chop", "pork loin", "pork tenderloin", "pork shoulder" ] },
            "lamb" => { aliases: [ "lamb chop", "leg of lamb", "lamb shoulder" ] },
            "veal" => {},
            "venison" => {},
            "bison" => {},
            "rabbit" => {},
            "goat" => { aliases: [ "goat meat" ] }
          }
        },
        "common grains and starches" => {
          kind: :category,
          children: {
            "rice" => { aliases: [ "white rice", "brown rice", "jasmine rice", "basmati rice", "arborio rice",
                                   "long grain rice", "short grain rice", "rice flour" ] },
            "wild rice" => {},
            "quinoa" => {},
            # Member of gluten (cross-contact), not a wheat product.
            "oat" => { aliases: [ "rolled oats", "oatmeal", "steel cut oats", "quick oats", "old fashioned oats",
                                  "oat flour", "oat bran", "oat milk" ] },
            "corn" => {
              aliases: [ "sweet corn", "corn kernels", "corn on the cob", "cornmeal", "cornstarch", "corn starch",
                         "maize" ],
              children: { "corn oil" => {} }
            },
            "millet" => {},
            "buckwheat" => { aliases: [ "buckwheat groats", "kasha", "buckwheat flour" ] },
            "amaranth" => {},
            "sorghum" => {},
            "teff" => {},
            "tapioca" => { aliases: [ "tapioca starch", "tapioca flour" ] },
            "arrowroot" => {}
          }
        },
        "common legumes" => {
          kind: :category,
          children: {
            "black bean" => { aliases: [ "black turtle bean" ] },
            "kidney bean" => { aliases: [ "red kidney bean" ] },
            "pinto bean" => {},
            "navy bean" => {},
            "cannellini bean" => { aliases: [ "white bean", "great northern bean" ] },
            "lima bean" => { aliases: [ "butter bean" ] },
            "chickpea" => { aliases: [ "garbanzo", "garbanzo bean" ] },
            "lentil" => { aliases: [ "brown lentil", "red lentil", "green lentil", "french lentil" ] },
            "split pea" => { aliases: [ "yellow split pea", "green split pea" ] },
            "black eyed pea" => { aliases: [ "black-eyed pea" ] },
            "mung bean" => {},
            "adzuki bean" => { aliases: [ "azuki bean" ] },
            "fava bean" => { aliases: [ "broad bean" ] },
            "pigeon pea" => {},
            "cranberry bean" => { aliases: [ "borlotti bean" ] }
          }
        },
        "common vegetables" => {
          kind: :category,
          children: {
            "broccoli" => { aliases: [ "broccoli florets" ] },
            "cauliflower" => { aliases: [ "cauliflower florets" ] },
            "carrot" => {},
            "celery" => { aliases: [ "celery stalk" ] },
            "onion" => { aliases: [ "sweet onion", "onion powder" ] },
            "scallion" => { aliases: [ "green onion", "spring onion" ] },
            "shallot" => {},
            "leek" => {},
            "garlic" => { aliases: [ "garlic clove", "garlic powder" ] },
            "bell pepper" => { aliases: [ "sweet pepper", "capsicum" ] },
            "jalapeno" => { aliases: [ "jalapeño", "jalapeno pepper", "jalapeño pepper" ] },
            "zucchini" => { aliases: [ "courgette" ] },
            "yellow squash" => { aliases: [ "summer squash" ] },
            "butternut squash" => {},
            "acorn squash" => {},
            "spaghetti squash" => {},
            "pumpkin" => { aliases: [ "pumpkin puree" ] },
            "eggplant" => { aliases: [ "aubergine" ] },
            "cucumber" => {},
            # The alias keeps "butter lettuce" from reading as butter (milk).
            "lettuce" => { aliases: [ "romaine", "romaine lettuce", "iceberg lettuce", "butter lettuce",
                                      "leaf lettuce", "bibb lettuce" ] },
            "kale" => {},
            "cabbage" => { aliases: [ "napa cabbage", "savoy cabbage" ] },
            "bok choy" => { aliases: [ "pak choi" ] },
            "collard greens" => { aliases: [ "collards" ] },
            "swiss chard" => { aliases: [ "chard" ] },
            "arugula" => { aliases: [ "rocket" ] },
            "watercress" => {},
            "asparagus" => {},
            "green bean" => { aliases: [ "string bean", "haricot vert", "haricots verts" ] },
            "pea" => { aliases: [ "green pea", "garden pea" ] },
            "snow pea" => {},
            "snap pea" => { aliases: [ "sugar snap pea" ] },
            "mushroom" => { aliases: [ "button mushroom", "cremini", "cremini mushroom", "portobello",
                                       "portobello mushroom", "shiitake", "shiitake mushroom" ] },
            "beet" => { aliases: [ "beetroot" ] },
            "radish" => {},
            "turnip" => {},
            "parsnip" => {},
            "sweet potato" => { aliases: [ "sweet potatoes" ] },
            "yam" => {},
            "artichoke" => { aliases: [ "artichoke heart" ] },
            "brussels sprout" => { aliases: [ "brussel sprout" ] },
            "okra" => {},
            "fennel" => { aliases: [ "fennel bulb", "fennel seed" ] },
            "tomatillo" => {},
            "celeriac" => { aliases: [ "celery root" ] },
            "kohlrabi" => {},
            "rutabaga" => { aliases: [ "swede" ] },
            "jicama" => {},
            "bean sprout" => { aliases: [ "mung bean sprout" ] },
            # A corm, not a nut; the FDA does not list it as a tree nut.
            "water chestnut" => {},
            "endive" => { aliases: [ "belgian endive" ] },
            "radicchio" => {},
            "chayote" => {},
            "daikon" => { aliases: [ "daikon radish" ] },
            "taro" => { aliases: [ "taro root" ] },
            "cassava" => { aliases: [ "yuca" ] },
            "bamboo shoot" => {}
          }
        },
        "common fruits" => {
          kind: :category,
          children: {
            "apple" => {},
            "pear" => {},
            "peach" => {},
            "nectarine" => {},
            "plum" => {},
            "apricot" => { children: { "dried apricot" => {} } },
            "cherry" => {},
            "grape" => {},
            "strawberry" => {},
            "blueberry" => {},
            "raspberry" => {},
            "blackberry" => {},
            # Dried cranberries are almost always sweetened: a member of added sugar.
            "cranberry" => { children: { "dried cranberry" => { aliases: [ "craisin" ] } } },
            "raisin" => {},
            "prune" => { aliases: [ "dried plum" ] },
            "date" => { aliases: [ "medjool date" ] },
            "fig" => {},
            "mango" => { aliases: [ "mangoes" ] },
            "pineapple" => {},
            "papaya" => {},
            "kiwi" => { aliases: [ "kiwifruit", "kiwi fruit" ] },
            "cantaloupe" => {},
            "honeydew" => { aliases: [ "honeydew melon" ] },
            "watermelon" => {},
            "lemon" => { aliases: [ "lemon juice", "lemon zest" ] },
            "lime" => { aliases: [ "lime juice", "lime zest" ] },
            # Grapefruit interacts with many medications; nurses often mark it cannot.
            "grapefruit" => { aliases: [ "grapefruit juice" ] },
            "tangerine" => { aliases: [ "mandarin", "mandarin orange", "clementine" ] },
            "pomegranate" => { aliases: [ "pomegranate seeds", "pomegranate arils" ] },
            "plantain" => {},
            "lychee" => { aliases: [ "litchi" ] },
            "guava" => {},
            "passion fruit" => {},
            "persimmon" => {},
            "star fruit" => { aliases: [ "carambola" ] },
            "gooseberry" => {},
            "currant" => {},
            "mulberry" => {},
            "boysenberry" => {},
            "elderberry" => {},
            "dragon fruit" => { aliases: [ "pitaya" ] },
            "jackfruit" => {},
            "quince" => {},
            "kumquat" => {},
            "rhubarb" => {},
            # The FDA no longer lists coconut as a tree nut, so it is a common
            # food. A nurse can add a cannot for a patient who reacts to it.
            "coconut" => {
              aliases: [ "shredded coconut", "coconut flakes", "coconut milk", "coconut cream" ],
              children: { "coconut oil" => {} }
            }
          }
        },
        "common herbs and single spices" => {
          kind: :category,
          children: {
            "basil" => {},
            "oregano" => {},
            "thyme" => {},
            "rosemary" => {},
            "parsley" => { aliases: [ "flat leaf parsley", "italian parsley" ] },
            "cilantro" => { aliases: [ "coriander leaves" ] },
            "coriander" => { aliases: [ "coriander seed" ] },
            "dill" => {},
            "mint" => { aliases: [ "mint leaves" ] },
            "sage" => {},
            "chives" => { aliases: [ "chive" ] },
            "bay leaf" => { aliases: [ "bay leaves" ] },
            "tarragon" => {},
            "cumin" => { aliases: [ "cumin seed" ] },
            "turmeric" => {},
            "cinnamon" => { aliases: [ "cinnamon stick" ] },
            # Nutmeg is a seed, not a tree nut (FDA).
            "nutmeg" => {},
            "ginger" => { aliases: [ "ginger root", "fresh ginger" ] },
            "paprika" => { aliases: [ "smoked paprika", "sweet paprika" ] },
            "cayenne" => { aliases: [ "cayenne pepper" ] },
            "black pepper" => { aliases: [ "pepper", "peppercorn", "white pepper" ] },
            "red pepper flakes" => { aliases: [ "crushed red pepper", "chili flakes" ] },
            "clove" => {},
            "cardamom" => {},
            "allspice" => {},
            "saffron" => {},
            "star anise" => {},
            "marjoram" => {},
            "lemongrass" => { aliases: [ "lemon grass" ] },
            "chervil" => {},
            "sumac" => {},
            "fenugreek" => {},
            "caraway seed" => { aliases: [ "caraway" ] },
            "juniper berry" => {},
            "vanilla bean" => { aliases: [ "vanilla pod" ] }
          }
        },
        "common seeds" => {
          kind: :category,
          children: {
            "chia seed" => { aliases: [ "chia" ] },
            "flaxseed" => { aliases: [ "flax", "flax seed", "linseed" ] },
            "pumpkin seed" => { aliases: [ "pepita" ] },
            "sunflower seed" => { children: { "sunflower oil" => {} } },
            "hemp seed" => { aliases: [ "hemp heart" ] },
            "poppy seed" => {}
          }
        },
        "common oils" => {
          kind: :category,
          children: {
            # Kept apart from olives, whose membership in sodium is about brine.
            "olive oil" => { aliases: [ "extra virgin olive oil", "evoo" ] },
            "canola oil" => { aliases: [ "rapeseed oil" ] },
            "safflower oil" => {},
            "grapeseed oil" => {}
          }
        },
        "common pantry items" => {
          kind: :category,
          children: {
            "water" => { aliases: [ "cold water", "warm water", "hot water", "boiling water", "ice water", "ice" ] },
            "vinegar" => { aliases: [ "white vinegar", "distilled vinegar", "apple cider vinegar", "cider vinegar",
                                      "rice vinegar", "red wine vinegar", "white wine vinegar" ] },
            "baking soda" => { aliases: [ "sodium bicarbonate", "bicarbonate of soda" ] },
            "agar" => { aliases: [ "agar agar" ] }
          }
        }
      }
    },
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
      members: [ "soy sauce", "fish sauce", "stock", "cured meat", "bacon", "ham", "pickles", "olives", "parmesan",
                 "baking soda" ]
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
      },
      members: [ "dried cranberry", "baked beans" ]
    },
    "potassium" => {
      kind: :nutrient,
      aliases: [ "low potassium", "renal diet", "kidney disease", "ckd", "chronic kidney disease" ],
      # High-potassium foods from common renal-diet lists. Kept to the clear cases.
      members: [ "banana", "potato", "tomato", "orange", "avocado", "spinach",
                 "sweet potato", "yam", "plantain", "pumpkin", "butternut squash", "acorn squash", "swiss chard",
                 "beet", "artichoke", "brussels sprout", "parsnip",
                 "black bean", "kidney bean", "pinto bean", "navy bean", "cannellini bean", "lima bean", "chickpea",
                 "lentil", "split pea",
                 "dried apricot", "raisin", "prune", "date", "cantaloupe", "honeydew", "kiwi", "mango", "papaya",
                 "pomegranate", "nectarine" ]
    }
  }.freeze
end
